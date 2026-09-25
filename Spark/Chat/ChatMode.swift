import Foundation

/// How a chat answers the next message, picked in the composer (Cursor-style) or cycled with ⇧Tab.
enum ChatMode: String, CaseIterable, Identifiable, Sendable {
    /// A plain reply from the model.
    case ask
    /// Deep research: web search and page reading, then an answer with citations (`ResearchAgent`).
    case research

    var id: Self { self }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .research: "Research"
        }
    }

    var systemImage: String {
        switch self {
        case .ask: "bubble.left"
        case .research: "globe"
        }
    }

    var summary: String {
        switch self {
        case .ask: "Chat with the model"
        case .research: "Search the web and read pages, then answer with sources"
        }
    }

    var placeholder: String {
        switch self {
        case .ask: "Ask anything…"
        case .research: "Research anything…"
        }
    }
}
