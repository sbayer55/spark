import Foundation

/// A source of chat completions (Ollama, Bifrost, 9router, Anthropic, …).
///
/// Providers are value-like and `Sendable` so streams can be produced off the main actor.
protocol LLMProvider: Sendable {
    /// Stable identifier used for persistence and selection.
    var id: String { get }
    /// Human-readable name shown in the model picker.
    var displayName: String { get }
    /// Models this provider can serve.
    var models: [String] { get }

    /// Streams the assistant's reply as incremental text chunks.
    /// Cancelling the consuming task must stop the underlying work.
    func stream(messages: [ChatMessage], model: String) -> AsyncThrowingStream<String, Error>
}

/// A provider + model pair selected in the UI.
struct ModelSelection: Hashable, Sendable {
    let providerID: String
    let model: String
}
