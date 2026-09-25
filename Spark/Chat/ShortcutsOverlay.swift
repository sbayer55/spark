import KeyboardShortcuts
import SwiftUI

/// The ⌘/ list of Spark's keyboard shortcuts, shown over the chat like the ⌃Tab switcher.
/// Key handling lives in `PanelController`; this view only draws.
struct ShortcutsOverlay: View {
    let store: ChatStore

    @State private var contentHeight: CGFloat = 0

    /// The list scrolls once it's taller than this.
    private static let maxHeight: CGFloat = 460

    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { action }
    }

    private struct Group: Identifiable {
        let title: String
        let shortcuts: [Shortcut]
        var id: String { title }
    }

    private var groups: [Group] {
        let toggle = KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "Not set"
        return [
            Group(title: "Spark", shortcuts: [
                Shortcut(keys: toggle, action: "Show or hide Spark (from any app)"),
                Shortcut(keys: "⌘,", action: "Settings"),
                Shortcut(keys: "⌘/", action: "Keyboard shortcuts"),
            ]),
            Group(title: "Chats", shortcuts: [
                Shortcut(keys: "⌘N", action: "New chat"),
                Shortcut(keys: "⌘W", action: "Close chat"),
                Shortcut(keys: "⌃Tab", action: "Switch chats (hold ⌃, press Tab)"),
                Shortcut(keys: "⌃⇧Tab", action: "Switch chats backward"),
            ]),
            Group(title: "Composer", shortcuts: [
                Shortcut(keys: "↩", action: "Send"),
                Shortcut(keys: "⇧↩", action: "New line"),
                Shortcut(keys: "Esc", action: "Stop the reply, or close Spark"),
            ]),
            Group(title: "Text size", shortcuts: [
                Shortcut(keys: "⌘+", action: "Larger"),
                Shortcut(keys: "⌘−", action: "Smaller"),
                Shortcut(keys: "⌘0", action: "Default size"),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                // One grid for every section, so the key column lines up across sections.
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                    ForEach(groups) { group in
                        GridRow {
                            Text(group.title)
                                .font(.headline)
                                .padding(.top, group.id == groups.first?.id ? 0 : 8)
                                .gridCellColumns(2)
                        }
                        ForEach(group.shortcuts) { shortcut in
                            GridRow {
                                keycap(shortcut.keys)
                                    .gridColumnAlignment(.trailing)
                                Text(shortcut.action)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, Self.maxHeight))

            Divider()
                .padding(.horizontal, 6)
            Text("Press ⌘/ or Esc to close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        }
        .padding(8)
        .panelBackground(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard Shortcuts")
    }

    private func keycap(_ keys: String) -> some View {
        Text(keys)
            .font(.system(.body, design: .rounded).weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: .rect(cornerRadius: 6, style: .continuous))
    }
}
