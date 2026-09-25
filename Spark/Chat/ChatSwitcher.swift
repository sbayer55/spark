import SwiftUI

/// The ⌃Tab chat switcher: open chats, most recently used first. Hold ⌃ and press Tab to move down
/// (⇧Tab up), then release ⌃ to switch. Arrow keys and Return also work; Escape cancels.
/// Key handling lives in `PanelController`; this view only draws `ChatStore`'s state.
struct ChatSwitcher: View {
    let store: ChatStore
    @Environment(\.theme) private var theme

    @State private var rowsHeight: CGFloat = 0

    /// The list scrolls once it's taller than this.
    private static let maxRowsHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(store.chats.enumerated()), id: \.element.id) { index, chat in
                            row(chat, isHighlighted: index == store.switcherIndex)
                                .id(chat.id)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                }
                .frame(height: min(rowsHeight, Self.maxRowsHeight))
                .onChange(of: store.switcherIndex) {
                    if let index = store.switcherIndex, store.chats.indices.contains(index) {
                        proxy.scrollTo(store.chats[index].id)
                    }
                }
            }

            Divider()
                .padding(.horizontal, 6)
            Text("Release ⌃ to switch  ·  ⌘N New Chat  ·  ⌘W Close Chat")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        }
        .padding(8)
        .panelBackground(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch Chat")
    }

    private func row(_ chat: ChatViewModel, isHighlighted: Bool) -> some View {
        Button {
            store.activate(chat)
        } label: {
            HStack(spacing: 10) {
                indicator(for: chat, isHighlighted: isHighlighted)
                    .frame(width: 12)
                Text(chat.title)
                    .fontWeight(chat.hasUnreadReply ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(detail(for: chat))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(isHighlighted ? highlightedText : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func indicator(for chat: ChatViewModel, isHighlighted: Bool) -> some View {
        if chat.isStreaming {
            ProgressView()
                .controlSize(.mini)
        } else if chat.hasUnreadReply {
            Circle()
                .fill(isHighlighted ? highlightedText : AnyShapeStyle(.tint))
                .frame(width: 7, height: 7)
                .accessibilityLabel("Unread reply")
        }
    }

    /// Text on the tint-filled highlight: the theme's background contrasts with its accent; white suits the system accent.
    private var highlightedText: AnyShapeStyle {
        AnyShapeStyle(theme?.background ?? .white)
    }

    private func detail(for chat: ChatViewModel) -> String {
        if chat.isActive { return "Current" }
        if chat.isStreaming { return "Replying…" }
        return chat.selection?.model ?? ""
    }
}
