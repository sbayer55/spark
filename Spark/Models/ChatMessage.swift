import Foundation

/// A single message in a chat transcript. Kept in memory only for now.
struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Hashable, Sendable {
        case user
        case assistant
        /// Instructions for the model. Only used in transient prompt arrays, never shown in the transcript.
        case system
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
    /// Non-nil for replies produced by research mode; holds the live step list and sources.
    var research: ResearchState?

    init(id: UUID = UUID(), role: Role, content: String, status: Status = .complete, research: ResearchState? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.research = research
    }
}
