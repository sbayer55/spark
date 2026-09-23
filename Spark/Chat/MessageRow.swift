import SwiftUI

struct MessageRow: View {
    let message: ChatMessage

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
            VStack(alignment: .leading, spacing: 4) {
                if message.content.isEmpty && message.status == .streaming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    MarkdownView(text: message.content)
                }
                statusLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch message.status {
        case .cancelled:
            Label("Stopped", systemImage: "stop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        case .complete, .streaming:
            EmptyView()
        }
    }
}
