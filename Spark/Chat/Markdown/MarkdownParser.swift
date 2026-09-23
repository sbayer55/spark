import Foundation
import Markdown

// This is the only file that imports `Markdown`: its `Text`, `Link`, `Image`, and `Table`
// types clash with SwiftUI's, so everything else works with `MarkdownBlock`.

/// Converts markdown source (CommonMark + GFM) into `MarkdownBlock`s.
enum MarkdownParser {
    static func blocks(from source: String) -> [MarkdownBlock] {
        blocks(in: Document(parsing: source).children)
    }

    private static func blocks(in children: MarkupChildren) -> [MarkdownBlock] {
        children.compactMap(block)
    }

    private static func block(_ markup: any Markup) -> MarkdownBlock? {
        switch markup {
        case let paragraph as Paragraph:
            .paragraph(inlines(paragraph))
        case let heading as Heading:
            .heading(level: heading.level, inlines(heading))
        case let code as CodeBlock:
            .codeBlock(
                language: code.language.flatMap { $0.isEmpty ? nil : $0 },
                code: code.code.trimmingCharacters(in: .newlines)
            )
        case let quote as BlockQuote:
            .blockQuote(blocks(in: quote.children))
        case let list as UnorderedList:
            .list(ordered: false, start: 1, items: listItems(list.children))
        case let list as OrderedList:
            .list(ordered: true, start: Int(list.startIndex), items: listItems(list.children))
        case let table as Table:
            .table(
                header: table.head.cells.map { inlines($0) },
                rows: table.body.rows.map { $0.cells.map { inlines($0) } }
            )
        case is ThematicBreak:
            .thematicBreak
        case let html as HTMLBlock:
            .paragraph(AttributedString(html.rawHTML.trimmingCharacters(in: .newlines)))
        default:
            nil
        }
    }

    private static func listItems(_ children: MarkupChildren) -> [MarkdownListItem] {
        children.compactMap { $0 as? ListItem }.map { item in
            MarkdownListItem(
                checkbox: item.checkbox.map { $0 == .checked },
                blocks: blocks(in: item.children)
            )
        }
    }

    // MARK: - Inline content

    private static func inlines(_ markup: any Markup) -> AttributedString {
        inlines(markup.children, intent: [], link: nil)
    }

    private static func inlines(_ children: MarkupChildren, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        children.reduce(into: AttributedString()) { result, child in
            result += inline(child, intent: intent, link: link)
        }
    }

    private static func inline(_ markup: any Markup, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        switch markup {
        case let text as Text:
            styled(text.string, intent, link)
        case let code as InlineCode:
            styled(code.code, intent.union(.code), link)
        case is SoftBreak:
            styled(" ", intent, link)
        case is LineBreak:
            styled("\n", intent, link)
        case let html as InlineHTML:
            styled(html.rawHTML, intent, link)
        case let image as Image:
            styled(image.plainText, intent, link)
        case is Strong:
            inlines(markup.children, intent: intent.union(.stronglyEmphasized), link: link)
        case is Emphasis:
            inlines(markup.children, intent: intent.union(.emphasized), link: link)
        case is Strikethrough:
            inlines(markup.children, intent: intent.union(.strikethrough), link: link)
        case let anchor as Link:
            inlines(markup.children, intent: intent, link: anchor.destination.flatMap(URL.init(string:)) ?? link)
        default:
            inlines(markup.children, intent: intent, link: link)
        }
    }

    private static func styled(_ string: String, _ intent: InlinePresentationIntent, _ link: URL?) -> AttributedString {
        var result = AttributedString(string)
        if !intent.isEmpty { result.inlinePresentationIntent = intent }
        if let link { result.link = link }
        return result
    }
}
