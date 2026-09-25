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

extension MarkdownBlock {
    /// Applies `transform` to every piece of inline text in this block and its children.
    func mapInlines(_ transform: (AttributedString) -> AttributedString) -> MarkdownBlock {
        switch self {
        case .paragraph(let text):
            .paragraph(transform(text))
        case .heading(let level, let text):
            .heading(level: level, transform(text))
        case .codeBlock, .thematicBreak:
            self
        case .blockQuote(let blocks):
            .blockQuote(blocks.map { $0.mapInlines(transform) })
        case .list(let ordered, let start, let items):
            .list(ordered: ordered, start: start, items: items.map { item in
                MarkdownListItem(checkbox: item.checkbox, blocks: item.blocks.map { $0.mapInlines(transform) })
            })
        case .table(let header, let rows):
            .table(header: header.map(transform), rows: rows.map { $0.map(transform) })
        }
    }
}
