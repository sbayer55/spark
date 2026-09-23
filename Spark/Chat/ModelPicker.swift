import SwiftUI

/// Compact menu listing every provider's models, grouped by provider.
struct ModelPicker: View {
    @Bindable var model: ChatViewModel

    var body: some View {
        Menu {
            ForEach(model.registry.providers, id: \.id) { provider in
                Section(provider.displayName) {
                    ForEach(provider.models, id: \.self) { name in
                        let option = ModelSelection(providerID: provider.id, model: name)
                        Toggle(name, isOn: Binding(
                            get: { model.selection == option },
                            set: { if $0 { model.selection = option } }
                        ))
                    }
                }
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
        guard let selection = model.selection else { return "No model" }
        let providerName = model.registry.provider(id: selection.providerID)?.displayName ?? selection.providerID
        return "\(providerName) / \(selection.model)"
    }
}
