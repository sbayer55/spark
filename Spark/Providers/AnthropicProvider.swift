import Foundation

/// Claude via the Anthropic Messages API (`GET /v1/models`, `POST /v1/messages` with SSE streaming).
/// Only offered once an API key is set in Settings (see `ProviderRegistry`).
struct AnthropicProvider: LLMProvider {
    static let providerID = "anthropic"
    /// The Keychain account holding the API key.
    static let keychainAccount = "anthropic-api-key"
    private static let apiVersion = "2023-06-01"

    let id = AnthropicProvider.providerID
    let displayName = "Anthropic"
    let apiKey: String
    var baseURL = URL(string: "https://api.anthropic.com/v1")!
    var session: URLSession = .shared

    /// Newest first, as the API lists them.
    func availableModels() async throws -> [String] {
        var request = makeRequest(path: "models", method: "GET", timeout: 10)
        request.url?.append(queryItems: [URLQueryItem(name: "limit", value: "1000")])
        do {
            let (data, response) = try await session.data(for: request)
            try ProviderHTTP.validate(response, body: data)
            return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)
        } catch {
            throw mapError(error, url: request.url)
        }
    }

    func stream(messages: [ChatMessage], model: String) -> AsyncThrowingStream<String, Error> {
        var draftRequest = makeRequest(path: "messages", method: "POST", timeout: 300)
        draftRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let transcript = AlternatingTranscript(messages)
        let body = MessagesRequest(
            model: model,
            maxTokens: Self.maxOutputTokens(for: model),
            system: transcript.system,
            messages: transcript.turns.map { MessagesRequest.Message(role: $0.role.rawValue, content: $0.text) },
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
                        // Every event's `data:` payload carries its own `type`, so the `event:` lines can be skipped.
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        let event = try decoder.decode(StreamEvent.self, from: Data(payload.utf8))
                        switch event.type {
                        case "content_block_delta":
                            if let text = event.delta?.text, !text.isEmpty {
                                continuation.yield(text)
                            }
                        case "error":
                            throw ProviderError.server(event.error?.message ?? "Anthropic reported an error.")
                        default:
                            continue
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

    /// A reply-length cap each Claude model accepts (the API requires one). Older models have lower limits;
    /// newer ones allow far more, but this is plenty for a chat reply. Also used for Claude on Bedrock.
    static func maxOutputTokens(for model: String) -> Int {
        if model.contains("claude-3-5") { return 8_192 }
        if ["claude-3-haiku", "claude-3-sonnet", "claude-3-opus", "claude-2", "claude-instant"].contains(where: model.contains) {
            return 4_096
        }
        return 16_384
    }

    // MARK: - Helpers

    private func makeRequest(path: String, method: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        return request
    }

    private func mapError(_ error: any Error, url: URL?) -> any Error {
        ProviderHTTP.mapError(error, provider: displayName, url: url, fallbackURL: baseURL)
    }
}

// MARK: - Wire types

private struct ModelList: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct MessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream
        case maxTokens = "max_tokens"
    }
}

private struct StreamEvent: Decodable {
    /// Text for `text_delta`s; other delta types (thinking, tool input, `message_delta`) have none.
    struct Delta: Decodable { let text: String? }
    struct APIError: Decodable { let message: String }

    let type: String
    let delta: Delta?
    let error: APIError?
}
