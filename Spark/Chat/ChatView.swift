import SwiftUI

/// Root view hosted in the chat panel: a message list and a composer, each on Liquid Glass.
struct ChatView: View {
    @Bindable var model: ChatViewModel
    let layout: PanelLayout
    /// Reports the view's natural height so the panel can size itself to fit (only while the height isn't fixed).
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var listContentHeight: CGFloat = 0
    @AppStorage(TextSize.key) private var textScale = TextSize.defaultScale

    var body: some View {
        // Content-sized until the user resizes vertically; then the message list fills the panel.
        let fillsHeight = layout.isHeightFixed

        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if fillsHeight || !model.messages.isEmpty {
                    messageList(fillsHeight: fillsHeight)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                        .transition(.opacity)
                }
                ChatInput(model: model)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
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

    private func messageList(fillsHeight: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
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
            .onChange(of: scrollTrigger) {
                if let last = model.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// Changes whenever a message is added or the streaming message grows.
    private var scrollTrigger: Int {
        model.messages.count &* 1_000_003 &+ (model.messages.last?.content.count ?? 0)
    }
}
