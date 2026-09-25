import SwiftUI

/// The ⌘K chat history: every saved chat, newest first, narrowed by the search field. ↑↓ move the highlight,
/// ↩ opens, Esc closes. Key handling lives in `PanelController`; this view draws `ChatStore`'s state and takes typing.
struct ChatHistoryView: View {
    @Bindable var store: ChatStore
    @Environment(\.theme) private var theme
    @FocusState private var isSearchFocused: Bool

    @State private var rowsHeight: CGFloat = 0
    @State private var hoveredID: UUID?

    /// The list scrolls once it's taller than this.
    private static let maxRowsHeight: CGFloat = 320

    var body: some View {
        let results = store.historyResults
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search chats", text: $store.historyQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()
                .padding(.horizontal, 6)

            if results.isEmpty {
                Text(store.archive.records.isEmpty ? "No saved chats yet" : "No matching chats")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, record in
                                row(record, isHighlighted: index == store.historyIndex)
                                    .id(record.id)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                    }
                    .frame(height: min(rowsHeight, Self.maxRowsHeight))
                    .onChange(of: store.historyIndex) {
                        if results.indices.contains(store.historyIndex) {
                            proxy.scrollTo(results[store.historyIndex].id)
                        }
                    }
                }
            }

            Divider()
                .padding(.horizontal, 6)
            Text("↑↓ Move  ·  ↩ Open  ·  Esc Close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        }
        .padding(8)
        .panelBackground(cornerRadius: 18)
        .onAppear { isSearchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat History")
    }

    private func row(_ record: ChatRecord, isHighlighted: Bool) -> some View {
        let foreground = isHighlighted ? highlightedText : AnyShapeStyle(.primary)
        return HStack(spacing: 6) {
            Button {
                store.open(record)
            } label: {
                HStack(spacing: 10) {
                    Text(record.title)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(detail(for: record))
                        .foregroundStyle(isHighlighted ? highlightedText : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(record.title)

            Button("Delete", systemImage: "trash") {
                store.deleteFromHistory(record)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .opacity(isHighlighted || hoveredID == record.id ? 1 : 0)
            .accessibilityLabel("Delete \(record.title)")
            .help("Delete from history")
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 10, style: .continuous))
        .onHover { hoveredID = $0 ? record.id : (hoveredID == record.id ? nil : hoveredID) }
    }

    /// Text on the tint-filled highlight: the theme's background contrasts with its accent; white suits the system accent.
    private var highlightedText: AnyShapeStyle {
        AnyShapeStyle(theme?.background ?? .white)
    }

    private func detail(for record: ChatRecord) -> String {
        if store.isOpen(record) { return "Open" }
        return record.updatedAt.formatted(.relative(presentation: .named))
    }
}
