import SwiftUI

/// Root view hosted in the chat panel: the active chat's message list and composer on a single flat panel,
/// with the ⌃Tab switcher or ⌘/ shortcuts list over them while one is open.
struct ChatView: View {
    let store: ChatStore
    let layout: PanelLayout
    /// Reports the view's natural height so the panel can size itself to fit.
    var onHeightChange: (CGFloat) -> Void = { _ in }
    /// Hands over SwiftUI's `openSettings` action so the AppKit panel can open Settings (⌘,).
    var onOpenSettingsAction: (OpenSettingsAction) -> Void = { _ in }

    @Environment(\.openSettings) private var openSettings

    @State private var listContentHeight: CGFloat = 0
    /// Height of everything below the message list (divider and composer), to work out the list's share of the maximum.
    @State private var composerHeight: CGFloat = 0
    @AppStorage(TextSize.key) private var textScale = TextSize.defaultScale
    @AppStorage(Theme.key) private var themeID = Theme.systemID

    var body: some View {
        // Always content-sized: just the composer for an empty chat, growing as messages arrive up to the cap.
        let chat = store.active
        let isSwitching = store.isSwitcherOpen
        let isShowingShortcuts = store.isShowingShortcuts
        let isCovered = isSwitching || isShowingShortcuts
        let theme = Theme.named(themeID)

        // A ZStack so the panel grows to fit the switcher when it's taller than the chat.
        ZStack(alignment: .top) {
            // One flat panel: the message list and composer share a single background.
            VStack(spacing: 0) {
                if !chat.messages.isEmpty {
                    messageList(for: chat)
                        .id(chat.id)
                        .transition(.opacity)
                }
                VStack(spacing: 0) {
                    if !chat.messages.isEmpty {
                        Divider()
                            .padding(.horizontal, 14)
                    }
                    ChatInput(store: store, chat: chat)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
            }
            .panelBackground(cornerRadius: PanelMetrics.cornerRadius)
            .blur(radius: isCovered ? 3 : 0)
            .opacity(isCovered ? 0.5 : 1)
            .overlay {
                if isCovered {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            store.cancelSwitcher()
                            store.dismissShortcuts()
                        }
                }
            }

            if isSwitching {
                ChatSwitcher(store: store)
                    .padding(.horizontal, 32)
            } else if isShowingShortcuts {
                ShortcutsOverlay(store: store)
                    .padding(.horizontal, 32)
            }
        }
        .environment(\.textScale, textScale)
        .environment(\.theme, theme)
        .themeStyle(theme)
        // Writing Tools is off app-wide; there's no global switch, so each window root opts out.
        .writingToolsBehavior(.disabled)
        .padding(PanelMetrics.inset)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { onOpenSettingsAction(openSettings) }
    }

    /// The message list's height limit: what's left of the user's maximum panel height after the composer
    /// and inset, or the default cap.
    private var maxListHeight: CGFloat {
        guard let maxHeight = layout.maxHeight else { return PanelMetrics.maxListHeight }
        return max(PanelMetrics.minListHeight, maxHeight - composerHeight - 2 * PanelMetrics.inset)
    }

    private func messageList(for chat: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listContentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .defaultScrollAnchor(.bottom)
            .frame(height: min(listContentHeight, maxListHeight))
            .onChange(of: scrollTrigger(for: chat)) {
                if let last = chat.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// Changes whenever a message is added, the streaming message grows, or a research step updates.
    private func scrollTrigger(for chat: ChatViewModel) -> Int {
        var hasher = Hasher()
        hasher.combine(chat.messages.count)
        hasher.combine(chat.messages.last?.content.count ?? 0)
        hasher.combine(chat.messages.last?.research)
        return hasher.finalize()
    }
}
