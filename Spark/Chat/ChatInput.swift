import SwiftUI

/// Multi-line composer. Return sends, Shift+Return inserts a newline.
struct ChatInput: View {
    @Bindable var model: ChatViewModel
    @FocusState private var isFocused: Bool

    private static let maxLines = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            editor
            HStack {
                ModelPicker(model: model)
                Spacer()
                actionButton.composerButtonStyle()
            }
        }
        .padding(14)
        .onAppear { isFocused = true }
        .onChange(of: model.focusRequest) { isFocused = true }
    }

    /// A `TextEditor` sized by an invisible `Text` mirror so it grows with content up to `maxLines`.
    private var editor: some View {
        Text(model.draft.isEmpty ? " " : model.draft + " ")
            .lineLimit(1...Self.maxLines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            .hidden()
            .overlay {
                TextEditor(text: $model.draft)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($isFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        guard !press.modifiers.contains(.shift) else { return .ignored }
                        model.send()
                        return .handled
                    }
            }
            .overlay(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text("Ask anything…")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .scaledFont(size: 15)
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.isStreaming {
            Button("Stop", systemImage: "stop.circle.fill") { model.cancelStreaming() }
                .help("Stop generating (Esc)")
        } else {
            Button("Send", systemImage: "arrow.up.circle.fill") { model.send() }
                .disabled(!model.canSend)
                .help("Send (Return)")
        }
    }
}

private extension View {
    func composerButtonStyle() -> some View {
        self.labelStyle(.iconOnly)
            .font(.title2)
            .buttonStyle(.borderless)
    }
}
