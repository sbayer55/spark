import Foundation
import Observation

/// The providers available to the app and the models each one currently offers.
@MainActor
@Observable
final class ProviderRegistry {
    /// Built-in providers, followed by the user's custom ones.
    var providers: [any LLMProvider] {
        let custom = customProviders.providers
        // An imported 9router config supersedes its placeholder.
        let hasNineRouter = customProviders.configs.contains { $0.source == .nineRouter }
        let builtIn = builtInProviders.filter { !(hasNineRouter && $0.id == "9router") }
        return builtIn + custom
    }

    private let builtInProviders: [any LLMProvider]
    let customProviders: CustomProviders

    /// Models by provider ID, from the last refresh.
    private(set) var models: [String: [String]] = [:]
    /// Human-readable refresh failures by provider ID (e.g. Ollama not running).
    private(set) var errors: [String: String] = [:]
    private(set) var isRefreshing = false

    init(providers: [any LLMProvider] = ProviderRegistry.standardProviders,
         customProviders: CustomProviders = CustomProviders()) {
        self.builtInProviders = providers
        self.customProviders = customProviders
    }

    /// Providers whose last refresh failed (e.g. Ollama isn't running).
    var unavailableProviders: [any LLMProvider] {
        providers.filter { errors[$0.id] != nil }
    }

    func provider(id: String) -> (any LLMProvider)? {
        providers.first { $0.id == id }
    }

    func models(for providerID: String) -> [String] {
        models[providerID] ?? []
    }

    func contains(_ selection: ModelSelection) -> Bool {
        models(for: selection.providerID).contains(selection.model)
    }

    /// First model of the first provider that has any.
    var defaultSelection: ModelSelection? {
        for provider in providers {
            if let model = models(for: provider.id).first {
                return ModelSelection(providerID: provider.id, model: model)
            }
        }
        return nil
    }

    /// Re-queries every provider for its models, concurrently.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = self.providers
        // Forget providers that were removed since the last refresh.
        let ids = Set(providers.map(\.id))
        models = models.filter { ids.contains($0.key) }
        errors = errors.filter { ids.contains($0.key) }

        await withTaskGroup(of: (String, Result<[String], any Error>).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.availableModels()))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let list):
                    models[id] = list
                    errors[id] = nil
                case .failure(let error):
                    models[id] = []
                    errors[id] = error.localizedDescription
                }
            }
        }
    }

    nonisolated static var standardProviders: [any LLMProvider] {
        [
            Ollama.provider(),
            // TODO: Replace with a native Anthropic Messages API client (SSE streaming, API key from Keychain).
            MockProvider(id: "anthropic", displayName: "Anthropic", models: ["claude-sonnet"]),
            // TODO: Replace with an OpenAICompatibleProvider pointed at the Bifrost gateway.
            MockProvider(id: "bifrost", displayName: "Bifrost", models: ["gpt-4o"]),
            // TODO: Replace with an OpenAICompatibleProvider pointed at 9router.
            MockProvider(id: "9router", displayName: "9router", models: ["auto"]),
        ]
    }
}
