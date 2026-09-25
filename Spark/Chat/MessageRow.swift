import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    @Environment(\.theme) private var theme

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                MarkdownView(text: message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.tint.opacity(0.18), in: .rect(cornerRadius: 14, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if let research = message.research {
                    ResearchProgressView(research: research,
                                         isRunning: message.status == .streaming && message.content.isEmpty)
                }
                if message.content.isEmpty && message.status == .streaming && message.research == nil {
                    ProgressView()
                        .controlSize(.small)
                } else if !message.content.isEmpty || message.research == nil {
                    MarkdownView(text: message.content)
                }
                if let research = message.research, message.status != .streaming, !research.sources.isEmpty {
                    ResearchSourcesView(sources: research.sources)
                }
                statusLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .system:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch message.status {
        case .cancelled:
            Label("Stopped", systemImage: "stop.circle")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .scaledFont(.caption)
                .foregroundStyle(theme?.red ?? .red)
        case .complete, .streaming:
            EmptyView()
        }
    }
}
