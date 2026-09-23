import Foundation

/// The set of providers available to the app.
struct ProviderRegistry: Sendable {
    let providers: [any LLMProvider]

    func provider(id: String) -> (any LLMProvider)? {
        providers.first { $0.id == id }
    }

    /// First model of the first provider.
    var defaultSelection: ModelSelection? {
        guard let provider = providers.first, let model = provider.models.first else { return nil }
        return ModelSelection(providerID: provider.id, model: model)
    }

    static let standard = ProviderRegistry(providers: [
        // TODO: Replace with an OpenAI-compatible client pointed at the local Ollama server (http://localhost:11434/v1).
        MockProvider(id: "ollama", displayName: "Ollama", models: ["llama3.2"]),
        // TODO: Replace with a native Anthropic Messages API client (SSE streaming, API key from Keychain).
        MockProvider(id: "anthropic", displayName: "Anthropic", models: ["claude-sonnet"]),
        // TODO: Replace with an OpenAI-compatible client pointed at the Bifrost gateway.
        MockProvider(id: "bifrost", displayName: "Bifrost", models: ["gpt-4o"]),
        // TODO: Replace with an OpenAI-compatible client pointed at 9router.
        MockProvider(id: "9router", displayName: "9router", models: ["auto"]),
    ])
}
