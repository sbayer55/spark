import Foundation

/// A chat reshaped for APIs that take the system prompt separately and require turns that start with
/// the user and alternate (Anthropic Messages, Bedrock Converse).
///
/// Empty messages (e.g. a reply that failed before any text) are dropped, and the neighbours they leave
/// behind with the same role are merged, so retrying after a failure doesn't send two user turns in a row.
struct AlternatingTranscript {
    struct Turn {
        let role: ChatMessage.Role
        var text: String
    }

    /// Every system message, joined; `nil` when there are none.
    let system: String?
    /// User and assistant turns only, starting with a user turn.
    let turns: [Turn]

    init(_ messages: [ChatMessage]) {
        let systemTexts = messages.filter { $0.role == .system && !$0.content.isEmpty }.map(\.content)
        system = systemTexts.isEmpty ? nil : systemTexts.joined(separator: "\n\n")

        var turns: [Turn] = []
        for message in messages where message.role != .system && !message.content.isEmpty {
            if turns.isEmpty && message.role == .assistant { continue }
            if turns.last?.role == message.role {
                turns[turns.count - 1].text += "\n\n" + message.content
            } else {
                turns.append(Turn(role: message.role, text: message.content))
            }
        }
        self.turns = turns
    }
}
