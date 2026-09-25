import Foundation

/// Runs the deep-research loop on top of the plain text-streaming `LLMProvider` interface:
/// plan queries → search → read pages → (optional follow-up round) → stream a cited answer.
/// Progress is reported as `ResearchEvent`s; cancelling the consuming task stops all work.
struct ResearchAgent: Sendable {
    let provider: any LLMProvider
    let model: String
    let search: BraveSearchClient
    let reader: PageReader
    /// The user's system prompt. Only the final answer uses it: the planning steps need their strict JSON
    /// instructions, which a custom prompt could override.
    var systemPrompt: String?

    enum Limits {
        static let maxRounds = 2
        static let queriesPerRound = [4, 2]
        static let pagesPerRound = 5
        static let maxPagesTotal = 8
        static let concurrentFetches = 4
        static let maxQueryLength = 200
    }

    typealias Note = (source: ResearchSource, text: String)

    func run(history: [ChatMessage]) -> AsyncThrowingStream<ResearchEvent, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    try await research(history: history, progress: Progress(continuation: continuation))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    // MARK: - Pipeline

    private func research(history: [ChatMessage], progress: Progress) async throws {
        let question = history.last(where: { $0.role == .user })?.content ?? ""

        // 1. Plan.
        let planning = progress.start("Planning searches…")
        var queries = await planQueries(history: history, fallback: question)
        progress.finish(planning, .done)

        var notes: [Note] = []
        var seenURLs: Set<String> = []
        var previousQueries: [String] = []

        // 2. Search and read, up to `maxRounds` times.
        for round in 0..<Limits.maxRounds {
            try Task.checkCancellation()
            if round > 0 {
                let checking = progress.start("Checking for gaps…")
                let more = await followUpQueries(history: history, notes: notes, previousQueries: previousQueries)
                progress.finish(checking, .done)
                guard let more, !more.isEmpty else { break }
                queries = more
            }
            let limit = Limits.queriesPerRound[min(round, Limits.queriesPerRound.count - 1)]
            queries = Array(queries.prefix(limit))
            previousQueries += queries

            let results = try await searchAll(queries, progress: progress)
            let remaining = min(Limits.pagesPerRound, Limits.maxPagesTotal - notes.count)
            let candidates = Self.candidates(from: results, seen: &seenURLs, limit: remaining)
            guard !candidates.isEmpty else { continue }

            notes += await readAll(candidates, startingAt: notes.count + 1, progress: progress)
            progress.sources(notes.map(\.source))
            if notes.count >= Limits.maxPagesTotal { break }
        }

        try Task.checkCancellation()

        // 3. Synthesize.
        let synthesizing = progress.start("Synthesizing answer…")
        let instructions = [systemPrompt, ResearchPrompts.synthesis(notes: notes)].compactMap(\.self)
        let messages = [ChatMessage(role: .system, content: instructions.joined(separator: "\n\n"))] + history
        var first = true
        for try await chunk in provider.stream(messages: messages, model: model) {
            if first {
                progress.finish(synthesizing, .done)
                first = false
            }
            progress.answer(chunk)
        }
        if first { progress.finish(synthesizing, .done) }
        progress.sources(notes.map(\.source))
    }

    private func planQueries(history: [ChatMessage], fallback: String) async -> [String] {
        let messages = [ChatMessage(role: .system, content: ResearchPrompts.planner())] + history
        let text = (try? await provider.complete(messages: messages, model: model)) ?? ""
        let parsed = Self.parseQueries(from: text)?.queries ?? []
        if !parsed.isEmpty { return parsed }
        let single = Self.normalize(fallback)
        return single.isEmpty ? [] : [single]
    }

    /// Nil means the model considers the notes sufficient (or didn't answer usefully).
    private func followUpQueries(history: [ChatMessage], notes: [Note], previousQueries: [String]) async -> [String]? {
        let prompt = ResearchPrompts.followUp(notes: notes, previousQueries: previousQueries)
        let messages = [ChatMessage(role: .system, content: prompt)] + history
        guard let text = try? await provider.complete(messages: messages, model: model),
              let parsed = Self.parseQueries(from: text), !parsed.done
        else { return nil }
        let lowercased = Set(previousQueries.map { $0.lowercased() })
        let fresh = parsed.queries.filter { !lowercased.contains($0.lowercased()) }
        return fresh.isEmpty ? nil : fresh
    }

    /// Searches every query concurrently. Each query gets its own step; a failed query contributes
    /// nothing unless every query failed the same way (bad key, rate limit), which aborts the run.
    private func searchAll(_ queries: [String], progress: Progress) async throws -> [[BraveSearchClient.Result]] {
        var results = Array(repeating: [BraveSearchClient.Result](), count: queries.count)
        var failures: [ResearchError] = []

        try await withThrowingTaskGroup(of: (Int, Result<[BraveSearchClient.Result], any Error>).self) { group in
            for (index, query) in queries.enumerated() {
                // Started here, not in the child task, so steps appear in planned order.
                let step = progress.start("Searching: \(query)")
                group.addTask {
                    do {
                        let found = try await search.search(query)
                        progress.finish(step, .done)
                        return (index, .success(found))
                    } catch is CancellationError {
                        progress.finish(step, .cancelled)
                        throw CancellationError()
                    } catch {
                        progress.finish(step, .failed(error.localizedDescription))
                        return (index, .failure(error))
                    }
                }
            }
            for try await (index, outcome) in group {
                switch outcome {
                case .success(let found): results[index] = found
                case .failure(let error): if let error = error as? ResearchError { failures.append(error) }
                }
            }
        }

        if failures.count == queries.count, let fatal = failures.first(where: Self.isFatal) {
            throw fatal
        }
        return results
    }

    private static func isFatal(_ error: ResearchError) -> Bool {
        switch error {
        case .searchRejected, .searchRateLimited, .missingAPIKey: true
        case .searchFailed: false
        }
    }

    /// Interleaves results across queries so each query contributes its top hit first, then dedupes.
    private static func candidates(
        from results: [[BraveSearchClient.Result]], seen: inout Set<String>, limit: Int
    ) -> [BraveSearchClient.Result] {
        guard limit > 0 else { return [] }
        var picked: [BraveSearchClient.Result] = []
        let longest = results.map(\.count).max() ?? 0
        for position in 0..<longest {
            for list in results where position < list.count {
                let result = list[position]
                guard let url = PageReader.fetchableURL(result.url) else { continue }
                let key = normalizedKey(url)
                guard seen.insert(key).inserted else { continue }
                picked.append(BraveSearchClient.Result(title: result.title, url: url, description: result.description))
                if picked.count >= limit { return picked }
            }
        }
        return picked
    }

    private static func normalizedKey(_ url: URL) -> String {
        var key = url.absoluteString
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            components.fragment = nil
            key = components.url?.absoluteString ?? key
        }
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }

    /// Reads pages with at most `concurrentFetches` in flight. Citation numbers follow candidate order.
    /// A page that fails to load still becomes a source, with the search snippet as its text.
    private func readAll(_ candidates: [BraveSearchClient.Result], startingAt firstID: Int, progress: Progress) async -> [Note] {
        var notes = Array<Note?>(repeating: nil, count: candidates.count)

        await withTaskGroup(of: (Int, Note).self) { group in
            var next = 0
            func enqueue() {
                guard next < candidates.count else { return }
                let index = next
                let candidate = candidates[index]
                let source = ResearchSource(id: firstID + index, title: Self.title(for: candidate), url: candidate.url)
                next += 1
                let step = progress.start("Reading \(source.host)")
                group.addTask {
                    do {
                        let text = try await reader.readableText(from: candidate.url)
                        progress.finish(step, text.isEmpty ? .failed("No readable text") : .done)
                        return (index, (source, text.isEmpty ? candidate.description : text))
                    } catch is CancellationError {
                        progress.finish(step, .cancelled)
                        return (index, (source, candidate.description))
                    } catch {
                        progress.finish(step, .failed(error.localizedDescription))
                        return (index, (source, candidate.description))
                    }
                }
            }
            for _ in 0..<Limits.concurrentFetches { enqueue() }
            for await (index, note) in group {
                notes[index] = note
                enqueue()
            }
        }
        return notes.compactMap { $0 }
    }

    private static func title(for result: BraveSearchClient.Result) -> String {
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (result.url.host() ?? result.url.absoluteString) : title
    }

    // MARK: - Parsing

    struct Plan {
        var queries: [String]
        var done: Bool
    }

    /// Extracts a query plan from model output, tolerating code fences, surrounding prose and
    /// bullet lists. Returns nil when nothing usable was found.
    static func parseQueries(from text: String) -> Plan? {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let json = jsonSlice(of: stripped),
           let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) {
            if let dictionary = object as? [String: Any] {
                let done = dictionary["done"] as? Bool ?? false
                let queries = (dictionary["queries"] as? [Any])?.compactMap { $0 as? String } ?? []
                return Plan(queries: dedupe(queries), done: done && queries.isEmpty)
            }
            if let array = object as? [Any] {
                return Plan(queries: dedupe(array.compactMap { $0 as? String }), done: false)
            }
        }

        // Fallback: bulleted or numbered lines.
        let lines = stripped.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var item = line.trimmingCharacters(in: .whitespaces)
            guard let marker = item.firstMatch(of: /^(?:[-*•]|\d+[.)])\s+/) else { return nil }
            item.removeSubrange(marker.range)
            return item.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
        }
        let queries = dedupe(lines)
        return queries.isEmpty ? nil : Plan(queries: queries, done: false)
    }

    private static func jsonSlice(of text: String) -> String? {
        guard let open = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let closer: Character = text[open] == "{" ? "}" : "]"
        guard let close = text.lastIndex(of: closer), close > open else { return nil }
        return String(text[open...close])
    }

    private static func dedupe(_ queries: [String]) -> [String] {
        var seen: Set<String> = []
        return queries.compactMap { raw in
            let query = normalize(raw)
            guard !query.isEmpty, seen.insert(query.lowercased()).inserted else { return nil }
            return query
        }
    }

    private static func normalize(_ query: String) -> String {
        let singleLine = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(singleLine.prefix(Limits.maxQueryLength))
    }

    // MARK: - Progress

    /// Thin wrapper over the stream continuation so steps read naturally at call sites.
    private struct Progress: Sendable {
        let continuation: AsyncThrowingStream<ResearchEvent, Error>.Continuation

        func start(_ title: String) -> UUID {
            let step = ResearchStep(title: title)
            continuation.yield(.stepStarted(step))
            return step.id
        }

        func finish(_ id: UUID, _ status: ResearchStep.Status) {
            continuation.yield(.stepFinished(id, status))
        }

        func sources(_ sources: [ResearchSource]) {
            continuation.yield(.sources(sources))
        }

        func answer(_ chunk: String) {
            continuation.yield(.answer(chunk))
        }
    }
}
