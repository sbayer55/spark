import SwiftUI

/// Multi-line composer. Return sends, Shift+Return inserts a newline.
struct ChatInput: View {
    let store: ChatStore
    @Bindable var chat: ChatViewModel
    @FocusState private var isFocused: Bool

    private static let maxLines = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            editor
            HStack {
                ModePicker(chat: chat)
                Spacer(minLength: 8)
                ModelPicker(store: store, chat: chat)
                actionButton.composerButtonStyle()
                    .fixedSize()
            }
        }
        .padding(14)
        .onAppear { isFocused = true }
        // The ⌘K history list has its own search field, which keeps the keyboard until it closes.
        .onChange(of: store.focusRequest) { if !store.isHistoryOpen { isFocused = true } }
    }

    /// A `TextEditor` sized by an invisible `Text` mirror so it grows with content up to `maxLines`.
    private var editor: some View {
        Text(chat.draft.isEmpty ? " " : chat.draft + " ")
            .lineLimit(1...Self.maxLines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            .hidden()
            .overlay {
                TextEditor(text: $chat.draft)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($isFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        guard !press.modifiers.contains(.shift) else { return .ignored }
                        chat.send()
                        return .handled
                    }
            }
            .overlay(alignment: .topLeading) {
                if chat.draft.isEmpty {
                    Text(chat.effectiveMode.placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .scaledFont(size: 15)
    }

    @ViewBuilder
    private var actionButton: some View {
        if chat.isStreaming {
            Button("Stop", systemImage: "stop.circle.fill") { chat.cancelStreaming() }
                .help("Stop generating (Esc)")
        } else {
            Button("Send", systemImage: "arrow.up.circle.fill") { chat.send() }
                .disabled(!chat.canSend)
                .help("Send (Return)")
        }
    }
}

private extension View {
    func composerButtonStyle() -> some View {
        self.labelStyle(.iconOnly)
            .scaledFont(.title2)
            .buttonStyle(.borderless)
    }
}
