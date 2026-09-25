import Foundation

/// opencode's `opencode.json[c]` (`provider` section) and `auth.json` (keys saved by `/connect`).
///
/// ```jsonc
/// "provider": {
///   "my-gateway": {
///     "npm": "@ai-sdk/openai-compatible",
///     "name": "My Gateway",
///     "options": { "baseURL": "https://gateway.example/v1", "apiKey": "{env:GATEWAY_KEY}" },
///     "models": { "model-a": { "name": "Model A" } }
///   }
/// }
/// ```
enum OpencodeConfig {
    static func providerID(_ opencodeID: String) -> String {
        "\(ProviderConfigSource.opencode.rawValue).\(opencodeID)"
    }

    static func readConfig(_ data: Data, fileName: String, into context: inout ProviderImporter.Context) throws {
        // JSON5 covers opencode's JSONC: comments and trailing commas.
        guard let root = try JSONSerialization.jsonObject(with: data, options: .json5Allowed) as? [String: Any],
              let providers = root["provider"] as? [String: Any], !providers.isEmpty
        else {
            context.notes.append("\(fileName): no providers configured.")
            return
        }

        for (id, value) in providers.sorted(by: { $0.key < $1.key }) {
            guard let entry = value as? [String: Any] else { continue }
            let options = entry["options"] as? [String: Any] ?? [:]
            let npm = entry["npm"] as? String ?? ""
            let known = KnownEndpoint.named(id)
            let name = entry["name"] as? String ?? known?.name ?? id

            if KnownEndpoint.isUnsupported(id) || KnownEndpoint.isUnsupported(npm) {
                context.notes.append("\(name): skipped; Spark only supports OpenAI-compatible APIs so far.")
                continue
            }
            guard let baseURL = KnownEndpoint.baseURL(options["baseURL"] as? String) ?? known?.baseURL else {
                context.notes.append("\(name): skipped; no base URL.")
                continue
            }

            let models = (entry["models"] as? [String: Any] ?? [:]).keys.sorted()
            let key = keyReference(options["apiKey"] as? String, fileName: fileName, context: &context)
            context.add(ProviderImporter.Draft(
                sourceKey: id,
                config: CustomProviderConfig(id: providerID(id), name: name, baseURL: baseURL, models: models,
                                             source: .opencode),
                key: key,
                fallbackKey: .opencodeAuth(id)
            ))
        }
    }

    /// `~/.local/share/opencode/auth.json`: `{ "<provider>": { "type": "api", "key": "…" } }`.
    /// OAuth entries are skipped: their tokens are tied to opencode's own client.
    static func readAuth(_ data: Data, into context: inout ProviderImporter.Context) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderImportError("Not an opencode auth.json file.")
        }
        for (id, value) in root {
            guard let entry = value as? [String: Any], entry["type"] as? String == "api",
                  let key = entry["key"] as? String, !key.isEmpty
            else { continue }
            context.opencodeAuth[id] = key

            // A key for a well-known provider is enough to add it, if the picked config didn't.
            if let known = KnownEndpoint.named(id), !context.drafts.contains(where: { $0.config.id == providerID(id) }) {
                context.add(ProviderImporter.Draft(
                    sourceKey: id,
                    config: CustomProviderConfig(id: providerID(id), name: known.name, baseURL: known.baseURL,
                                                 models: [], source: .opencode),
                    key: .opencodeAuth(id),
                    isKeyOnly: true
                ))
            }
        }
    }

    /// opencode's `{env:VAR}` and `{file:path}` substitutions, or a literal key.
    private static func keyReference(_ value: String?, fileName: String,
                                     context: inout ProviderImporter.Context) -> ProviderImporter.KeyReference {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return .none }
        if value.hasPrefix("{env:"), value.hasSuffix("}") {
            return .environment(String(value.dropFirst(5).dropLast()))
        }
        if value.hasPrefix("{file:"), value.hasSuffix("}") {
            let path = String(value.dropFirst(6).dropLast())
            let expanded = path.hasPrefix("~/")
                ? ProviderImporter.homeDirectory.appending(path: String(path.dropFirst(2))).path(percentEncoded: false)
                : path
            // Readable only if it happens to be inside something the user picked.
            if let key = try? String(contentsOfFile: expanded, encoding: .utf8) {
                return .literal(key.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            context.notes.append("\(fileName): couldn't read the key file \(path); add the key in Settings.")
            return .none
        }
        return .literal(value)
    }
}
