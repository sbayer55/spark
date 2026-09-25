import Foundation

/// System prompts for the research pipeline. Every prompt is sent as a leading `.system` message
/// ahead of the chat history, which already ends with the user's question.
enum ResearchPrompts {
    static func planner(today: Date = .now) -> String {
        """
        You are planning web research to answer the user's latest question. Today is \(dateString(today)).
        Write 2 to 4 short, specific web search queries that together cover what is needed to answer it well. \
        Avoid redundant queries. Use the conversation for context, but search for the latest question.
        Reply with ONLY this JSON, no prose and no code fences:
        {"queries": ["query one", "query two"]}
        """
    }

    static func followUp(notes: [(source: ResearchSource, text: String)], previousQueries: [String]) -> String {
        let previous = previousQueries.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        You are checking whether the research notes below are enough to answer the user's latest question.
        Reply with ONLY JSON, no prose and no code fences: {"done": true} if the notes are sufficient, \
        or {"queries": ["…"]} with 1 or 2 new web search queries that fill specific gaps.
        Do not repeat these queries: \(previous).

        # Notes so far
        \(render(notes, limit: 600))
        """
    }

    static func synthesis(notes: [(source: ResearchSource, text: String)], today: Date = .now) -> String {
        """
        You are a careful research assistant. Answer the user's latest question using the sources below. \
        Cite sources inline with bracketed numbers such as [1] or [2][3] right after the sentences they support; \
        every factual claim needs a citation. If sources disagree or don't cover something, say so rather than guessing. \
        Do not invent sources or citation numbers, and do not add a sources list — the app shows one. \
        Write in Markdown. Today is \(dateString(today)).

        # Sources
        \(render(notes, limit: nil))
        """
    }

    private static func render(_ notes: [(source: ResearchSource, text: String)], limit: Int?) -> String {
        notes.map { note in
            let body = limit.map { String(note.text.prefix($0)) } ?? note.text
            return "[\(note.source.id)] \(note.source.title) — \(note.source.url.absoluteString)\n\(body)"
        }
        .joined(separator: "\n\n")
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
