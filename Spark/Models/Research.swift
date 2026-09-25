import Foundation

/// Live progress and provenance of a research-mode reply. Attached to the assistant `ChatMessage`.
struct ResearchState: Hashable, Codable, Sendable {
    var steps: [ResearchStep] = []
    var sources: [ResearchSource] = []
}

/// One unit of work shown in the progress list ("Searching: …", "Reading example.com").
struct ResearchStep: Identifiable, Hashable, Codable, Sendable {
    enum Status: Hashable, Codable, Sendable {
        case running
        case done
        case failed(String)
        case cancelled
    }

    let id: UUID
    var title: String
    var status: Status

    init(id: UUID = UUID(), title: String, status: Status = .running) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// A page the agent read, numbered for inline citations.
struct ResearchSource: Identifiable, Hashable, Codable, Sendable {
    /// 1-based citation number, stable across rounds.
    let id: Int
    let title: String
    let url: URL

    var host: String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Emitted by `ResearchAgent.run`; consumed on the main actor by `ChatViewModel`.
enum ResearchEvent: Sendable {
    case stepStarted(ResearchStep)
    case stepFinished(UUID, ResearchStep.Status)
    case sources([ResearchSource])
    /// A streamed chunk of the final answer.
    case answer(String)
}
