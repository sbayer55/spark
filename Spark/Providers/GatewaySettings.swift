import Foundation
import Observation

/// A local OpenAI-compatible gateway (Bifrost, 9router), offered in the model picker once enabled in Settings.
/// The enabled flag, server URL, and optional model list live in `UserDefaults`; the API key in the Keychain.
@MainActor
@Observable
final class GatewaySettings {
    /// Which gateway: fixed identity plus the defaults and Settings copy that differ between them.
    struct Kind: Sendable {
        /// Provider ID, stable so a chat's remembered model keeps working.
        let id: String
        let displayName: String
        let defaultBaseURL: String
        /// `UserDefaults` key prefix, e.g. `bifrost` → `bifrostEnabled`, `bifrostBaseURL`, `bifrostModels`.
        let defaultsPrefix: String
        let keychainAccount: String
        /// Placeholder for the API key field.
        let keyPrompt: String
        /// Settings footer.
        let help: String

        static let bifrost = Kind(
            id: "bifrost",
            displayName: "Bifrost",
            defaultBaseURL: "http://localhost:8080/v1",
            defaultsPrefix: "bifrost",
            keychainAccount: "bifrost-api-key",
            keyPrompt: "Virtual key (optional)",
            help: "Bifrost's OpenAI-compatible gateway (getmaxim.ai/bifrost). A key is only needed when Bifrost's virtual keys are turned on. Models come from the gateway unless you list them here."
        )

        static let nineRouter = Kind(
            id: "9router",
            displayName: "9router",
            defaultBaseURL: "http://localhost:20128/v1",
            defaultsPrefix: "nineRouter",
            keychainAccount: "9router-api-key",
            keyPrompt: "API key from the 9router dashboard",
            help: "9router routes to the providers set up in its dashboard. Create an API key there, or import ~/.9router under Custom providers to fill this in. Models come from the router unless you list them here."
        )
    }

    let kind: Kind
    /// Bound in Settings; every set writes through to the Keychain.
    let apiKey: KeychainSecret

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    /// The API root as typed. `baseURL` falls back to the default while it isn't a usable URL.
    var baseURLText: String {
        didSet { UserDefaults.standard.set(baseURLText, forKey: baseURLKey) }
    }

    /// Comma- or newline-separated model names to offer instead of asking the server (`GET /models`).
    var modelsText: String {
        didSet { UserDefaults.standard.set(modelsText, forKey: modelsKey) }
    }

    init(kind: Kind) {
        self.kind = kind
        let defaults = UserDefaults.standard
        let prefix = kind.defaultsPrefix
        isEnabled = defaults.bool(forKey: prefix + "Enabled")
        baseURLText = defaults.string(forKey: prefix + "BaseURL") ?? ""
        modelsText = defaults.string(forKey: prefix + "Models") ?? ""
        apiKey = KeychainSecret(account: kind.keychainAccount)
    }

    var enabledKey: String { kind.defaultsPrefix + "Enabled" }
    var baseURLKey: String { kind.defaultsPrefix + "BaseURL" }
    var modelsKey: String { kind.defaultsPrefix + "Models" }

    /// The server URL from Settings, or the gateway's default when unset or invalid.
    var baseURL: URL {
        let text = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.scheme == "http" || url.scheme == "https", url.host() != nil {
            return url
        }
        return URL(string: kind.defaultBaseURL)!
    }

    /// Models listed in Settings, or empty to ask the server.
    var models: [String] {
        modelsText.split { $0 == "," || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The provider, or nil while the gateway is turned off.
    var provider: OpenAICompatibleProvider? {
        guard isEnabled else { return nil }
        let url = baseURL
        let key = apiKey.value
        return OpenAICompatibleProvider(
            id: kind.id,
            displayName: kind.displayName,
            baseURL: { url },
            apiKey: { key.isEmpty ? nil : key },
            configuredModels: models
        )
    }

    /// Fills in an imported config (see `ProviderImporter`) and turns the gateway on. A missing key keeps the stored one.
    func apply(baseURL: URL, apiKey: String?) {
        baseURLText = baseURL.absoluteString
        if let apiKey, !apiKey.isEmpty {
            self.apiKey.text = apiKey
        }
        isEnabled = true
    }
}
