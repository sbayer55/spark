import Foundation
import Observation

/// A user-added OpenAI-compatible endpoint, usually imported from another tool's config.
/// The API key isn't part of this value: it lives in the Keychain (see `CustomProviders`).
struct CustomProviderConfig: Codable, Hashable, Identifiable, Sendable {
    /// Stable across re-imports of the same source entry (e.g. `opencode.openrouter`), so a
    /// re-import updates the provider in place and a chat's remembered model keeps working.
    let id: String
    var name: String
    /// API root, e.g. `https://openrouter.ai/api/v1`.
    var baseURL: URL
    /// Models declared by the source config. Empty means "ask the server" (`GET /models`).
    var models: [String]
    var source: ProviderConfigSource
}

/// The tool a provider config was imported from.
enum ProviderConfigSource: String, Codable, Sendable, CaseIterable {
    case opencode
    case deepSeekHarness
    case nineRouter

    var displayName: String {
        switch self {
        case .opencode: "opencode"
        case .deepSeekHarness: "DeepSeek Harness"
        case .nineRouter: "9router"
        }
    }
}

/// Custom providers: configs in `UserDefaults`, API keys in the Keychain, both mirrored in memory
/// so the model picker and Settings stay in sync through Observation.
@MainActor
@Observable
final class CustomProviders {
    static let defaultsKey = "customProviders"

    private(set) var configs: [CustomProviderConfig]
    /// API keys by provider ID. Missing or empty means no key.
    private var keys: [String: String]

    init() {
        configs = Self.storedConfigs()
        keys = [:]
        loadKeys()
        ConfigFile.onReload { [weak self] in self?.reload() }
    }

    private static func storedConfigs() -> [CustomProviderConfig] {
        let stored = UserDefaults.standard.data(forKey: defaultsKey)
        return stored.flatMap { try? JSONDecoder().decode([CustomProviderConfig].self, from: $0) } ?? []
    }

    /// Reads the Keychain for providers whose key isn't loaded yet.
    private func loadKeys() {
        for config in configs where keys[config.id] == nil {
            if let key = try? Keychain.string(account: Self.keychainAccount(for: config.id)) {
                keys[config.id] = key
            }
        }
    }

    /// Picks up an edit to the config file. Keys of removed providers stay in the Keychain, so re-adding
    /// the entry brings its key back.
    private func reload() {
        let stored = Self.storedConfigs()
        guard stored != configs else { return }
        configs = stored
        loadKeys()
    }

    /// Live providers for the registry, rebuilt whenever a config or key changes.
    var providers: [any LLMProvider] {
        configs.map { config in
            let key = keys[config.id]
            return OpenAICompatibleProvider(
                id: config.id,
                displayName: config.name,
                baseURL: { config.baseURL },
                apiKey: { key },
                configuredModels: config.models
            )
        }
    }

    func apiKey(for id: String) -> String {
        keys[id] ?? ""
    }

    func setAPIKey(_ key: String, for id: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keys[id] = trimmed.isEmpty ? nil : trimmed
        try? Keychain.set(trimmed, account: Self.keychainAccount(for: id))
    }

    /// Adds imported providers, replacing any earlier import of the same entry, and fills in keys
    /// for already-imported providers. A re-import without a key keeps the key already stored.
    func apply(_ report: ProviderImportReport) {
        for (id, key) in report.keys where configs.contains(where: { $0.id == id }) {
            setAPIKey(key, for: id)
        }
        for provider in report.providers {
            if let index = configs.firstIndex(where: { $0.id == provider.config.id }) {
                if provider.replacesExisting { configs[index] = provider.config }
            } else {
                configs.append(provider.config)
            }
            if let key = provider.apiKey, !key.isEmpty {
                setAPIKey(key, for: provider.config.id)
            }
        }
        save()
    }

    func remove(id: String) {
        configs.removeAll { $0.id == id }
        setAPIKey("", for: id)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func keychainAccount(for id: String) -> String {
        "provider-api-key.\(id)"
    }
}
