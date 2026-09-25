import SwiftUI

/// Settings section listing custom providers, with import from opencode, DeepSeek Harness, and 9router.
struct CustomProvidersSection: View {
    let store: ChatStore
    @State private var isImporting = false
    @State private var summary: ImportSummary?

    private var customProviders: CustomProviders { store.registry.customProviders }

    var body: some View {
        Section {
            ForEach(customProviders.configs) { config in
                CustomProviderRow(config: config, customProviders: customProviders) {
                    customProviders.remove(id: config.id)
                    refreshModels()
                } onKeyCommitted: {
                    refreshModels()
                }
            }
            Button("Import Provider Config…") {
                isImporting = true
            }
        } header: {
            Text("Custom providers")
        } footer: {
            Text("Choose a config file or folder: ~/.config/opencode (and ~/.local/share/opencode for its keys), ~/.dsh for DeepSeek Harness, or ~/.9router. API keys are stored in your Keychain.")
                .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder, .item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importConfigs(from: urls)
            case .failure(let error):
                summary = ImportSummary(title: "Couldn't import", message: error.localizedDescription)
            }
        }
        .fileDialogDefaultDirectory(ProviderImporter.homeDirectory)
        .fileDialogBrowserOptions(.includeHiddenFiles)
        .alert(summary?.title ?? "", isPresented: Binding(
            get: { summary != nil },
            set: { if !$0 { summary = nil } }
        )) {
            Button("OK") { summary = nil }
        } message: {
            Text(summary?.message ?? "")
        }
    }

    private func importConfigs(from urls: [URL]) {
        let report = ProviderImporter.importConfigs(from: urls)
        customProviders.apply(report)
        refreshModels()

        let names = report.providers.map(\.config.name)
        let title = switch (names.count, report.keys.isEmpty) {
        case (0, true): "Nothing to import"
        case (0, false): "Updated API keys"
        case (1, _): "Imported \(names[0])"
        default: "Imported \(names.count) providers"
        }
        var lines = names.count > 1 ? [names.joined(separator: ", ")] : []
        lines += report.notes
        summary = ImportSummary(title: title, message: lines.joined(separator: "\n\n"))
    }

    private func refreshModels() {
        Task { await store.refreshModels() }
    }
}

private struct ImportSummary {
    let title: String
    let message: String
}

private struct CustomProviderRow: View {
    let config: CustomProviderConfig
    let customProviders: CustomProviders
    let onRemove: () -> Void
    let onKeyCommitted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                    Text("\(config.baseURL.absoluteString) · from \(config.source.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Remove", systemImage: "minus.circle", action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Remove \(config.name)")
            }
            SecureField("API key", text: Binding(
                get: { customProviders.apiKey(for: config.id) },
                set: { customProviders.setAPIKey($0, for: config.id) }
            ), prompt: Text("API key (optional for local servers)"))
            .textContentType(.password)
            .autocorrectionDisabled()
            .labelsHidden()
            .onSubmit(onKeyCommitted)
        }
        .padding(.vertical, 2)
    }
}
