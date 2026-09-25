import SwiftUI

/// Live list of research steps shown inside an assistant reply. Expanded while research runs,
/// collapses (and stays toggleable) once the answer starts streaming or the run ends.
struct ResearchProgressView: View {
    let research: ResearchState
    let isRunning: Bool

    @State private var isExpanded = true
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.snappy) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text(headline)
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .scaledFont(.caption)
            .foregroundStyle(.secondary)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(research.steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.map { AnyShapeStyle($0.surface) } ?? AnyShapeStyle(.primary.opacity(0.05)),
                    in: .rect(cornerRadius: 10, style: .continuous))
        .onChange(of: isRunning) { _, running in
            if !running {
                withAnimation(.snappy) { isExpanded = false }
            }
        }
    }

    private var headline: String {
        if isRunning { return "Researching…" }
        if research.steps.contains(where: { $0.status == .cancelled }) { return "Research stopped" }
        let count = research.sources.count
        return count == 1 ? "Researched 1 source" : "Researched \(count) sources"
    }
}

private struct StepRow: View {
    let step: ResearchStep
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            icon
                .frame(width: 14, alignment: .center)
            Text(step.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .scaledFont(.caption)
        .foregroundStyle(step.status == .running ? .primary : .secondary)
        .help(helpText)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme?.green ?? .green)
        case .failed:
            Image(systemName: "xmark.circle")
        case .cancelled:
            Image(systemName: "minus.circle")
        }
    }

    private var helpText: String {
        if case .failed(let reason) = step.status { return reason }
        return step.title
    }
}

/// Numbered, clickable list of the pages a research reply cites.
struct ResearchSourcesView: View {
    let sources: [ResearchSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Sources")
                .fontWeight(.semibold)
            ForEach(sources) { source in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("[\(source.id)]")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Link(source.title, destination: source.url)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(source.host)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .scaledFont(.caption)
        .padding(.top, 4)
    }
}
