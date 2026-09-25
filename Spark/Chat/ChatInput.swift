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
                ModelPicker(store: store, chat: chat)
                researchToggle
                Spacer()
                actionButton.composerButtonStyle()
                    .fixedSize()
            }
        }
        .padding(14)
        .onAppear { isFocused = true }
        .onChange(of: store.focusRequest) { isFocused = true }
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
                    Text(chat.researchEnabled ? "Research anything…" : "Ask anything…")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .scaledFont(size: 15)
    }

    /// Sticky per chat; disabled until a Brave Search API key is set in Settings.
    private var researchToggle: some View {
        Toggle(isOn: $chat.researchEnabled) {
            Label("Research", systemImage: "globe")
        }
        .toggleStyle(ChipToggleStyle())
        .scaledFont(.callout, maxSize: TextSize.maxControlFontSize)
        .fixedSize()
        .disabled(!chat.isResearchAvailable)
        .help(chat.isResearchAvailable
              ? "Search the web and read pages before answering"
              : "Add a Brave Search API key in Settings to enable Research")
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

/// A capsule toggle drawn in SwiftUI so its text, padding, and shape all follow the text size
/// (the system `.button` toggle style sizes its bezel and label by control size, ignoring the font).
private struct ChipToggleStyle: ToggleStyle {
    @Environment(\.textScale) private var scale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            let scale = TextSize.controlScale(for: scale)
            configuration.label
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 3 * scale)
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .background(configuration.isOn ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary),
                            in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private extension View {
    func composerButtonStyle() -> some View {
        self.labelStyle(.iconOnly)
            .scaledFont(.title2)
            .buttonStyle(.borderless)
    }
}
