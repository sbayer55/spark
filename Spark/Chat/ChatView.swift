import SwiftUI

/// Root view hosted in the chat panel: a message list and a composer, each on Liquid Glass.
struct ChatView: View {
    @Bindable var model: ChatViewModel
    /// Reports the view's natural height so the panel can size itself to fit.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var listContentHeight: CGFloat = 0

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if !model.messages.isEmpty {
                    messageList
                        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                        .transition(.opacity)
                }
                ChatInput(model: model)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
            }
        }
        .padding(PanelMetrics.inset)
        .frame(width: PanelMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var messageList: some View {
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
            .frame(height: min(listContentHeight, PanelMetrics.maxListHeight))
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
