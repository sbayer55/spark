import Foundation

/// A source of chat completions (Ollama, Bifrost, 9router, Anthropic, …).
///
/// Providers are value-like and `Sendable` so requests can run off the main actor.
protocol LLMProvider: Sendable {
    /// Stable identifier used for selection.
    var id: String { get }
    /// Human-readable name shown in the model picker.
    var displayName: String { get }

    /// Models this provider can currently serve. May hit the network.
    func availableModels() async throws -> [String]

    /// Streams the assistant's reply as incremental text chunks.
    /// Cancelling the consuming task must stop the underlying work.
    func stream(messages: [ChatMessage], model: String) -> AsyncThrowingStream<String, Error>
}

/// A provider + model pair selected in the UI.
struct ModelSelection: Hashable, Sendable {
    let providerID: String
    let model: String
}

/// Errors surfaced to the user from real (network-backed) providers.
enum ProviderError: LocalizedError {
    case unreachable(provider: String, url: URL)
    case http(status: Int, message: String?)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unreachable(let provider, let url):
            "Can't reach \(provider) at \(url.absoluteString). Is it running?"
        case .http(let status, let message):
            message ?? "Request failed (HTTP \(status))."
        case .server(let message):
            message
        case .invalidResponse:
            "The server sent a response Spark couldn't understand."
        }
    }
}

extension LLMProvider {
    /// Collects a whole reply, for prompt-and-parse steps that need the full text (e.g. a JSON plan).
    func complete(messages: [ChatMessage], model: String) async throws -> String {
        var text = ""
        for try await chunk in stream(messages: messages, model: model) {
            text += chunk
        }
        return text
    }
}
