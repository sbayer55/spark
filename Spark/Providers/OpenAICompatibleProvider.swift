import Foundation

/// Streams chat completions from any server implementing the OpenAI Chat Completions API
/// (`GET /models`, `POST /chat/completions` with SSE streaming). Used for Ollama; Bifrost
/// and 9router can reuse it with their own base URL and API key.
struct OpenAICompatibleProvider: LLMProvider {
    let id: String
    let displayName: String
    /// The API root (e.g. `http://localhost:11434/v1`). Resolved per request so Settings changes apply immediately.
    let baseURL: @Sendable () -> URL
    /// Optional bearer token. Resolved per request.
    var apiKey: @Sendable () -> String? = { nil }
    var session: URLSession = .shared

    func availableModels() async throws -> [String] {
        let request = makeRequest(path: "models", method: "GET", timeout: 5)
        do {
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, body: data)
            let list = try JSONDecoder().decode(ModelList.self, from: data)
            return list.data.map(\.id).sorted()
        } catch {
            throw mapError(error, url: request.url)
        }
    }

    func stream(messages: [ChatMessage], model: String) -> AsyncThrowingStream<String, Error> {
        var draftRequest = makeRequest(path: "chat/completions", method: "POST", timeout: 300)
        draftRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body = ChatRequest(
            model: model,
            messages: messages
                .filter { !$0.content.isEmpty }
                .map { ChatRequest.Message(role: $0.role.rawValue, content: $0.content) },
            stream: true
        )
        do {
            draftRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let request = draftRequest

        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 64_000 { break }
                        }
                        throw ProviderError.http(status: http.statusCode, message: Self.errorMessage(in: body))
                    }

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        // SSE: only `data:` lines carry payloads; skip comments, `event:`, blanks.
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }

                        let chunk = try decoder.decode(ChatChunk.self, from: Data(payload.utf8))
                        if let message = chunk.error?.message {
                            throw ProviderError.server(message)
                        }
                        if let text = chunk.choices?.first?.delta?.content, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapError(error, url: request.url))
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: baseURL().appending(path: path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey(), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func mapError(_ error: any Error, url: URL?) -> any Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
            let root = url.flatMap(Self.origin) ?? baseURL()
            return ProviderError.unreachable(provider: displayName, url: root)
        default:
            return urlError
        }
    }

    /// `scheme://host[:port]` of a URL, for user-facing messages.
    private static func origin(of url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host()
        components.port = url.port
        return components.url
    }

    private static func validate(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(status: http.statusCode, message: errorMessage(in: body))
        }
    }

    /// Extracts `{"error": {"message": …}}` or `{"error": "…"}` from an error body.
    private static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if let error = object["error"] as? [String: Any] { return error["message"] as? String }
        return object["error"] as? String
    }
}

// MARK: - Wire types

private struct ModelList: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
    }

    struct APIError: Decodable { let message: String }

    let choices: [Choice]?
    let error: APIError?
}
