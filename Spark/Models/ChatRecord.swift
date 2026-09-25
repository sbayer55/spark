import Foundation

/// A chat as saved by `ChatArchive`: the transcript plus what's needed to reopen it where it left off.
struct ChatRecord: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    /// When the chat last changed; the history list is ordered by it.
    var updatedAt: Date
    var mode: ChatMode
    var selection: ModelSelection?
    var messages: [ChatMessage]

    /// Whether the title or any message contains `query`, ignoring case.
    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || messages.contains { $0.content.localizedCaseInsensitiveContains(query) }
    }
}

extension ChatMessage {
    /// This message as it's saved: a reply still streaming is recorded as stopped, since there's no stream to
    /// resume once it's read back, and any research step still running with it is stopped too.
    var settled: ChatMessage {
        guard status == .streaming else { return self }
        var message = self
        message.status = .cancelled
        if var research = message.research {
            for index in research.steps.indices where research.steps[index].status == .running {
                research.steps[index].status = .cancelled
            }
            message.research = research
        }
        return message
    }
}
