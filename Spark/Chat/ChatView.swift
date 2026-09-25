import SwiftUI

/// Root view hosted in the chat panel: the active chat's message list and composer, each on Liquid Glass,
/// with the ⌃Tab switcher over them while it's open.
struct ChatView: View {
    let store: ChatStore
    let layout: PanelLayout
    /// Reports the view's natural height so the panel can size itself to fit (only while the height isn't fixed).
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var listContentHeight: CGFloat = 0
    @AppStorage(TextSize.key) private var textScale = TextSize.defaultScale

    var body: some View {
        // Content-sized until the user resizes vertically; then the message list fills the panel.
        let fillsHeight = layout.isHeightFixed
        let chat = store.active
        let isSwitching = store.isSwitcherOpen

        // A ZStack so the panel grows to fit the switcher when it's taller than the chat.
        ZStack(alignment: .top) {
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    if !chat.messages.isEmpty {
                        messageList(for: chat, fillsHeight: fillsHeight)
                            .id(chat.id)
                            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                            .transition(.opacity)
                    } else if fillsHeight {
                        // No empty glass for a new chat; keep the composer at the bottom of the fixed-height panel.
                        Spacer(minLength: 0)
                    }
                    ChatInput(store: store, chat: chat)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                }
            }
            .blur(radius: isSwitching ? 3 : 0)
            .opacity(isSwitching ? 0.5 : 1)
            .overlay {
                if isSwitching {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { store.cancelSwitcher() }
                }
            }

            if isSwitching {
                ChatSwitcher(store: store)
                    .padding(.horizontal, 32)
            }
        }
        .environment(\.textScale, textScale)
        // Writing Tools is off app-wide; there's no global switch, so each window root opts out.
        .writingToolsBehavior(.disabled)
        .padding(PanelMetrics.inset)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: !fillsHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if !layout.isHeightFixed { onHeightChange(height) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func messageList(for chat: ChatViewModel, fillsHeight: Bool) -> some View {
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
            .frame(height: fillsHeight ? nil : min(listContentHeight, PanelMetrics.maxListHeight))
            .frame(maxHeight: fillsHeight ? .infinity : nil)
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
