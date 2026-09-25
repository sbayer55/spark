import AppKit
import SwiftUI

/// Renders markdown source as native SwiftUI views.
struct MarkdownView: View {
    let text: String
    /// Citation targets by number: each `[n]` in the text links to `citations[n]` (research replies).
    var citations: [Int: URL] = [:]

    @Environment(\.theme) private var theme

    var body: some View {
        let linkColor = theme?.accent ?? .accentColor
        MarkdownBlocksView(blocks: MarkdownParser.blocks(from: text).map { block in
            block.mapInlines { $0.linkingCitations(citations).styledLinks(color: linkColor) }
        })
        .scaledFont(.body)
        .textSelection(.enabled)
    }
}

private extension AttributedString {
    /// Turns each `[n]` with a known citation into a link to that source, outside code and existing links.
    func linkingCitations(_ citations: [Int: URL]) -> AttributedString {
        guard !citations.isEmpty else { return self }
        var result = self
        let text = String(characters)
        for match in text.matches(of: /\[(\d+)\]/) {
            guard let number = Int(match.1), let url = citations[number] else { continue }
            let lower = result.characters.index(result.startIndex,
                                                offsetBy: text.distance(from: text.startIndex, to: match.range.lowerBound))
            let upper = result.characters.index(lower, offsetBy: text[match.range].count)
            let isPlain = result[lower..<upper].runs.allSatisfy { run in
                run.link == nil && !(run.inlinePresentationIntent?.contains(.code) ?? false)
            }
            if isPlain { result[lower..<upper].link = url }
        }
        return result
    }

    /// Colors and underlines every link so it reads as one.
    func styledLinks(color: Color) -> AttributedString {
        var result = self
        for (link, range) in runs[\.link] where link != nil {
            result[range].foregroundColor = color
            result[range].underlineStyle = .single
        }
        return result
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var spacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(text)
                .scaledFont(Self.headingStyle(level), weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .blockQuote(let blocks):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.secondary)
                    .frame(width: 3)
                MarkdownBlocksView(blocks: blocks)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            ListBlockView(ordered: ordered, start: start, items: items)
        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows)
        case .thematicBreak:
            Divider()
        }
    }

    private static func headingStyle(_ level: Int) -> Font.TextStyle {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                    .scaledFont(.caption)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView(.horizontal) {
                Text(code)
                    .scaledFont(.callout, design: .monospaced)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.map { AnyShapeStyle($0.surface) } ?? AnyShapeStyle(.primary.opacity(0.06)),
                    in: .rect(cornerRadius: 10, style: .continuous))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private struct ListBlockView: View {
    let ordered: Bool
    let start: Int
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(index: index, item: item)
                        .frame(minWidth: 16, alignment: .trailing)
                    MarkdownBlocksView(blocks: item.blocks, spacing: 6)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(index: Int, item: MarkdownListItem) -> some View {
        if let checked = item.checkbox {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(.secondary)
        } else if ordered {
            Text("\(start + index).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TableBlockView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]

    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        Text(Self.cell(header, column)).bold()
                    }
                }
                Divider()
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            Text(Self.cell(rows[row], column))
                        }
                    }
                    if row < rows.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private static func cell(_ cells: [AttributedString], _ column: Int) -> AttributedString {
        column < cells.count ? cells[column] : AttributedString()
    }
}
