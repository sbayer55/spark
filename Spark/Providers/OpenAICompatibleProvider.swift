import Foundation

/// Streams chat completions from any server implementing the OpenAI Chat Completions API
/// (`GET /models`, `POST /chat/completions` with SSE streaming). Used for Ollama and for
/// custom providers imported from other tools (see `CustomProviders`).
struct OpenAICompatibleProvider: LLMProvider {
    let id: String
    let displayName: String
    /// The API root (e.g. `http://localhost:11434/v1`). Resolved per request so Settings changes apply immediately.
    let baseURL: @Sendable () -> URL
    /// Optional bearer token. Resolved per request.
    var apiKey: @Sendable () -> String? = { nil }
    /// Models declared up front (e.g. by an imported config). When non-empty, these are offered
    /// as-is instead of asking the server, since many gateways don't implement `GET /models`.
    var configuredModels: [String] = []
    var session: URLSession = .shared

    func availableModels() async throws -> [String] {
        if !configuredModels.isEmpty { return configuredModels }
        let request = makeRequest(path: "models", method: "GET", timeout: 5)
        do {
            let (data, response) = try await session.data(for: request)
            try ProviderHTTP.validate(response, body: data)
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
                    try await ProviderHTTP.validate(response, bytes: bytes)

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
        ProviderHTTP.mapError(error, provider: displayName, url: url, fallbackURL: baseURL())
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
