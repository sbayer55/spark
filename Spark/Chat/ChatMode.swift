import Foundation

/// How a chat answers the next message, picked in the composer (Cursor-style) or cycled with ⇧Tab.
/// Declaration order is the menu order and the ⇧Tab cycle.
enum ChatMode: String, CaseIterable, Identifiable, Sendable {
    /// A plain reply from the model.
    case ask
    /// A short, direct answer: the same plain reply, with a brevity instruction appended to the system prompt.
    case tldr
    /// Deep research: web search and page reading, then an answer with citations (`ResearchAgent`).
    case research

    var id: Self { self }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .tldr: "TL;DR"
        case .research: "Research"
        }
    }

    var systemImage: String {
        switch self {
        case .ask: "bubble.left"
        case .tldr: "bolt"
        case .research: "globe"
        }
    }

    var summary: String {
        switch self {
        case .ask: "Chat with the model"
        case .tldr: "A short, direct answer without the fluff"
        case .research: "Search the web and read pages, then answer with sources"
        }
    }

    var placeholder: String {
        switch self {
        case .ask: "Ask anything…"
        case .tldr: "Ask for the short version…"
        case .research: "Research anything…"
        }
    }

    /// Extra system instructions for the plain reply path, sent after the user's own system prompt.
    /// `nil` for modes that add none (Research builds its own prompts in `ResearchAgent`).
    var instructions: String? {
        switch self {
        case .ask, .research:
            nil
        case .tldr:
            """
            Answer in TL;DR style. Lead with the bottom line, in at most three short sentences. \
            No preamble, no restating the question, no caveats unless they change the answer, and no closing offers. \
            Use a list only when the answer is inherently a list, and keep it to a few items. Write in plain Markdown.
            """
        }
    }
}
