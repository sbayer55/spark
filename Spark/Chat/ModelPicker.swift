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
            Label(title, systemImage: "sparkle")
                .font(.callout)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
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
