import SwiftUI

/// Compact menu listing every provider's models, grouped by provider.
struct ModelPicker: View {
    let store: ChatStore
    let chat: ChatViewModel

    private var registry: ProviderRegistry { store.registry }

    var body: some View {
        Menu {
            ForEach(registry.providers, id: \.id) { provider in
                Section(provider.displayName) {
                    let names = registry.models(for: provider.id)
                    if let error = registry.errors[provider.id] {
                        Text(error)
                    } else if names.isEmpty {
                        Text(registry.isRefreshing ? "Loading…" : "No models available")
                    }
                    ForEach(names, id: \.self) { name in
                        let option = ModelSelection(providerID: provider.id, model: name)
                        Toggle(name, isOn: Binding(
                            get: { chat.selection == option },
                            set: { if $0 { chat.select(option) } }
                        ))
                    }
                }
            }
            Divider()
            Button("Refresh Models", systemImage: "arrow.clockwise") {
                Task { await store.refreshModels() }
            }
        } label: {
            // Drawn in SwiftUI (plain style, own chevron) so it follows the text size; the system menu
            // button draws its label with AppKit and ignores the font.
            HStack(spacing: 4) {
                Label(title, systemImage: "sparkle")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.tint)
            .scaledFont(.callout, maxSize: TextSize.maxControlFontSize)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // Truncates (rather than pushing the Research and Send buttons out) when the text size outgrows the panel.
        .fixedSize(horizontal: false, vertical: true)
        .help("Choose a model")
    }

    private var title: String {
        guard let selection = chat.selection else {
            return registry.isRefreshing ? "Loading models…" : "Choose a model"
        }
        let providerName = registry.provider(id: selection.providerID)?.displayName ?? selection.providerID
        return "\(providerName) / \(selection.model)"
    }
}
