import SwiftUI

/// Cursor-style mode switch at the start of the composer row: a pill showing the chat's mode that opens a
/// menu of modes. ⇧Tab cycles modes from the keyboard (handled in `PanelController`).
struct ModePicker: View {
    @Bindable var chat: ChatViewModel
    @Environment(\.textScale) private var textScale

    var body: some View {
        let mode = chat.effectiveMode
        let scale = TextSize.controlScale(for: textScale)
        Menu {
            ForEach(ChatMode.allCases) { option in
                Toggle(isOn: Binding(
                    get: { mode == option },
                    set: { if $0 { chat.mode = option } }
                )) {
                    Label(option.title, systemImage: option.systemImage)
                    Text(chat.isAvailable(option) ? option.summary : "Add a Brave Search API key in Settings")
                }
                .disabled(!chat.isAvailable(option))
            }
            Divider()
            Text("⇧Tab to switch modes")
        } label: {
            // Drawn in SwiftUI so it follows the text size; the system menu button ignores the font.
            HStack(spacing: 4 * scale) {
                Label(mode.title, systemImage: mode.systemImage)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(mode == .ask ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 3 * scale)
            .background(mode == .ask ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint.opacity(0.2)), in: .capsule)
            .scaledFont(.callout, maxSize: TextSize.maxControlFontSize)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a mode (⇧Tab)")
        .accessibilityLabel("Mode: \(mode.title)")
    }
}
