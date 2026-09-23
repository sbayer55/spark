import Foundation

/// Renderer-facing markdown model. Inline content is an `AttributedString` using Foundation
/// presentation intents and links, which SwiftUI `Text` renders natively.
indirect enum MarkdownBlock: Hashable, Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case codeBlock(language: String?, code: String)
    case blockQuote([MarkdownBlock])
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case table(header: [AttributedString], rows: [[AttributedString]])
    case thematicBreak
}

struct MarkdownListItem: Hashable, Sendable {
    /// `nil` for a regular item; `true`/`false` for a checked/unchecked task item.
    var checkbox: Bool?
    var blocks: [MarkdownBlock]
}
