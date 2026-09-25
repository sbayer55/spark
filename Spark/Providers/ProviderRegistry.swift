import Foundation
import Observation

/// The providers available to the app and the models each one currently offers.
@MainActor
@Observable
final class ProviderRegistry {
    /// Ollama, then Anthropic and Bedrock once they have credentials, then the Bifrost and 9router gateways
    /// once they're turned on, then the user's custom providers.
    var providers: [any LLMProvider] {
        var hosted: [any LLMProvider] = []
        if anthropicKey.hasValue {
            hosted.append(AnthropicProvider(apiKey: anthropicKey.value))
        }
        if let bedrock = bedrock.provider {
            hosted.append(bedrock)
        }
        let gateways = [bifrost, nineRouter].compactMap(\.provider)
        return builtInProviders + hosted + gateways + customProviders.providers
    }

    private let builtInProviders: [any LLMProvider]
    let customProviders: CustomProviders
    /// The Anthropic API key; Anthropic is offered only while it's set.
    let anthropicKey: KeychainSecret
    /// Bedrock's region and credentials; Bedrock is offered only once they're filled in.
    let bedrock: BedrockSettings
    /// The Bifrost gateway; offered only while it's turned on in Settings.
    let bifrost: GatewaySettings
    /// The 9router gateway; offered only while it's turned on in Settings.
    let nineRouter: GatewaySettings

    /// Models by provider ID, from the last refresh.
    private(set) var models: [String: [String]] = [:]
    /// Human-readable refresh failures by provider ID (e.g. Ollama not running).
    private(set) var errors: [String: String] = [:]
    private(set) var isRefreshing = false

    init(providers: [any LLMProvider] = [Ollama.provider()],
         customProviders: CustomProviders = CustomProviders(),
         anthropicKey: KeychainSecret = KeychainSecret(account: AnthropicProvider.keychainAccount),
         bedrock: BedrockSettings = BedrockSettings(),
         bifrost: GatewaySettings = GatewaySettings(kind: .bifrost),
         nineRouter: GatewaySettings = GatewaySettings(kind: .nineRouter)) {
        self.builtInProviders = providers
        self.customProviders = customProviders
        self.anthropicKey = anthropicKey
        self.bedrock = bedrock
        self.bifrost = bifrost
        self.nineRouter = nineRouter
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
}
