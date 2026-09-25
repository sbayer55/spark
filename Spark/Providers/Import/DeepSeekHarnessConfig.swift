import Foundation
import Yams

/// DeepSeek Harness (`dsh`) provider config: `$DSH_HOME/settings.yaml` (default `~/.dsh`) or a profile's
/// `profiles/<profile>/cordis.patch.yml`, with keys in `.credentials.yaml` or `.env`.
///
/// ```yaml
/// agent-default-model:
///   provider: deepseek-official
///   model: deepseek-v4-flash
/// llm-pi-ai:
///   providers:
///     my-gateway:
///       apiKeyEnv: GATEWAY_API_KEY
///       api: openai-completions
///       baseURL: https://gateway.example/v1
///       models:
///         - id: model-name
/// ```
enum DeepSeekHarnessConfig {
    static func providerID(_ dshID: String) -> String {
        "\(ProviderConfigSource.deepSeekHarness.rawValue).\(dshID)"
    }

    static func readSettings(_ yaml: String, fileName: String, into context: inout ProviderImporter.Context) throws {
        guard let root = try Yams.load(yaml: yaml) else {
            context.notes.append("\(fileName): empty.")
            return
        }
        let found = context.drafts.count

        // `providers` sits under `llm-pi-ai` in settings.yaml, and under a plugin entry's `config` in
        // cordis.patch.yml; find it wherever it is.
        for providers in providerMaps(in: root) {
            for (id, value) in providers.sorted(by: { $0.key < $1.key }) {
                guard let entry = value as? [String: Any] else { continue }
                addProvider(id: id, entry: entry, fileName: fileName, into: &context)
            }
        }

        // The default model may name a built-in provider (e.g. `deepseek-official`) with no entry of its own.
        if let defaultModel = (root as? [String: Any])?["agent-default-model"] as? [String: Any],
           let id = defaultModel["provider"] as? String,
           !context.drafts.contains(where: { $0.config.id == providerID(id) }),
           let known = KnownEndpoint.named(id) {
            // Every model the provider serves is offered, not just the default.
            context.add(ProviderImporter.Draft(
                sourceKey: id,
                config: CustomProviderConfig(id: providerID(id), name: known.name, baseURL: known.baseURL,
                                             models: [], source: .deepSeekHarness),
                key: .environment(known.keyVariable)
            ))
        }

        if context.drafts.count == found {
            context.notes.append("\(fileName): no providers configured.")
        }
    }

    /// `.credentials.yaml` stores keys that `apiKeyEnv` refers to. Its layout isn't documented, so every
    /// string value is taken as a variable named by its key, and a `key`/`apiKey`/`value` string as the key
    /// of the provider (or variable) it's nested under.
    static func readCredentials(_ yaml: String, into context: inout ProviderImporter.Context) throws {
        guard let root = try Yams.load(yaml: yaml) else { return }
        collectStrings(root, parent: nil, into: &context)
    }

    // MARK: - Helpers

    private static func addProvider(id: String, entry: [String: Any], fileName: String,
                                    into context: inout ProviderImporter.Context) {
        let known = KnownEndpoint.named(id)
        let name = entry["name"] as? String ?? entry["displayName"] as? String ?? known?.name ?? id
        let api = entry["api"] as? String ?? "openai-completions"
        guard api == "openai-completions", !KnownEndpoint.isUnsupported(id) else {
            context.notes.append("\(name): skipped; Spark doesn't support the \(api) API yet.")
            return
        }
        guard let baseURL = KnownEndpoint.baseURL(entry["baseURL"] as? String) ?? known?.baseURL else {
            context.notes.append("\(name): skipped; no base URL.")
            return
        }

        let models = (entry["models"] as? [Any] ?? []).compactMap { model -> String? in
            if let id = model as? String { return id }
            return (model as? [String: Any])?["id"] as? String
        }
        let key: ProviderImporter.KeyReference = if let literal = entry["apiKey"] as? String {
            .literal(literal)
        } else if let variable = entry["apiKeyEnv"] as? String {
            .environment(variable)
        } else {
            .none
        }
        context.add(ProviderImporter.Draft(
            sourceKey: id,
            config: CustomProviderConfig(id: providerID(id), name: name, baseURL: baseURL, models: models,
                                         source: .deepSeekHarness),
            key: key,
            fallbackKey: known.map { .environment($0.keyVariable) } ?? .none
        ))
    }

    /// Every `providers:` mapping whose entries look like provider configs.
    private static func providerMaps(in node: Any) -> [[String: Any]] {
        if let list = node as? [Any] {
            return list.flatMap(providerMaps)
        }
        guard let map = node as? [String: Any] else { return [] }
        if let providers = map["providers"] as? [String: Any],
           providers.values.contains(where: { ($0 as? [String: Any]).map(looksLikeProvider) ?? false }) {
            return [providers]
        }
        return map.values.flatMap(providerMaps)
    }

    private static func looksLikeProvider(_ entry: [String: Any]) -> Bool {
        ["baseURL", "api", "apiKeyEnv", "models"].contains { entry[$0] != nil }
    }

    private static let secretFields: Set = ["key", "apiKey", "api_key", "value", "token"]

    private static func collectStrings(_ node: Any, parent: String?, into context: inout ProviderImporter.Context) {
        if let map = node as? [String: Any] {
            for (key, value) in map {
                if let string = value as? String {
                    context.environment[key] = string
                    if let parent, secretFields.contains(key) {
                        context.credentialsByProvider[parent] = string
                        context.environment[parent] = string
                    }
                } else {
                    collectStrings(value, parent: key, into: &context)
                }
            }
        } else if let list = node as? [Any] {
            for item in list { collectStrings(item, parent: parent, into: &context) }
        }
    }
}
