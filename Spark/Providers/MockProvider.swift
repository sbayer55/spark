import Foundation

/// Streams canned responses word by word so the UI can be exercised without a network.
struct MockProvider: LLMProvider {
    let id: String
    let displayName: String
    let models: [String]

    func availableModels() async throws -> [String] {
        models
    }

    func stream(messages: [ChatMessage], model: String) -> AsyncThrowingStream<String, Error> {
        let response = cannedResponse(for: messages, model: model)

        return AsyncThrowingStream { continuation in
            let producer = Task {
                let words = response.split(separator: " ", omittingEmptySubsequences: false)
                do {
                    for (index, word) in words.enumerated() {
                        try await Task.sleep(for: .milliseconds(Int.random(in: 20...60)))
                        continuation.yield(index == words.count - 1 ? String(word) : word + " ")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private func cannedResponse(for messages: [ChatMessage], model: String) -> String {
        let lastUserMessage = messages.last(where: { $0.role == .user })?.content ?? ""
        let responses = [
            "You said: “\(lastUserMessage)”. The plumbing works — this reply came from \(displayName) / \(model), streamed one token at a time.",
            "This is a mocked response from \(displayName). Real network calls aren't wired up yet, but streaming, cancellation, and auto-scroll are all live. Try pressing Escape mid-sentence to stop me.",
            "Here's a longer canned answer so you can watch the panel grow. Spark is a menu bar app for quick AI chats across several providers. Once real clients land, this text will be replaced by actual model output. Until then, enjoy these carefully chosen placeholder words, delivered with a small random delay between each one to mimic a real model. Keep sending messages and the panel will eventually hit its maximum height and start scrolling instead.",
        ]
        return responses.randomElement() ?? responses[0]
    }
}
