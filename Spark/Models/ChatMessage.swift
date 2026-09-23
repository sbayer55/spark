import Foundation

/// A single message in a chat transcript. Kept in memory only for now.
struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Hashable, Sendable {
        case user
        case assistant
    }

    enum Status: Hashable, Sendable {
        case complete
        case streaming
        case cancelled
        case failed(String)
    }

    let id: UUID
    let role: Role
    var content: String
    var status: Status

    init(id: UUID = UUID(), role: Role, content: String, status: Status = .complete) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
    }
}
