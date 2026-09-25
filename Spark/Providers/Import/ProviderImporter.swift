import Foundation

/// A provider found in another tool's config, ready to add to `CustomProviders`.
struct ImportedProvider: Sendable {
    var config: CustomProviderConfig
    var apiKey: String?
    /// False when only a key was found (opencode's `auth.json`): an earlier import of this provider
    /// is kept as-is, apart from the key.
    var replacesExisting = true
}

/// What an import found, plus notes for anything that couldn't be imported as-is.
struct ProviderImportReport: Sendable {
    var providers: [ImportedProvider] = []
    /// Keys for providers that may have been imported earlier (opencode's `auth.json` imported on its own),
    /// by provider ID.
    var keys: [String: String] = [:]
    var notes: [String] = []

    var isEmpty: Bool { providers.isEmpty && keys.isEmpty }
}

struct ProviderImportError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

/// Reads provider configs from opencode, DeepSeek Harness, and 9router.
///
/// Spark is sandboxed, so it can only read what the user picks in an open panel: a config file
/// or a whole config folder (`~/.config/opencode`, `~/.local/share/opencode`, `~/.dsh`, `~/.9router`).
/// Everything picked in one go is imported together, so e.g. a `.env` or credentials file can
/// supply the keys another file refers to.
enum ProviderImporter {
    /// Suggested starting folder for the open panel: the real home folder, not the sandbox container.
    static var homeDirectory: URL {
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            return URL(filePath: String(cString: home), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func importConfigs(from urls: [URL]) -> ProviderImportReport {
        var context = Context()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try readFolder(url, into: &context)
                } else {
                    try readFile(url, into: &context)
                }
            } catch {
                context.notes.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return context.finish()
    }

    // MARK: - Detection

    private static func readFolder(_ folder: URL, into context: inout Context) throws {
        let found = context.fileCount
        let candidates = [
            // 9router data folder (`~/.9router`) or its `db` folder.
            "db/data.sqlite", "data.sqlite", "db.json",
            // DeepSeek Harness home (`~/.dsh`).
            ".env", ".credentials.yaml", "settings.yaml",
            // opencode config (`~/.config/opencode`) and data (`~/.local/share/opencode`) folders.
            "opencode.json", "opencode.jsonc", "config.json", "auth.json",
        ]
        for path in candidates {
            let file = folder.appending(path: path)
            if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try readFile(file, into: &context)
            }
        }
        // DeepSeek Harness per-profile plugin config.
        let profiles = folder.appending(path: "profiles", directoryHint: .isDirectory)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: profiles.path(percentEncoded: false)) {
            for name in names.sorted() {
                let patch = profiles.appending(path: name).appending(path: "cordis.patch.yml")
                if FileManager.default.fileExists(atPath: patch.path(percentEncoded: false)) {
                    try readFile(patch, into: &context)
                }
            }
        }
        if context.fileCount == found {
            context.notes.append("\(folder.lastPathComponent): no opencode, DeepSeek Harness, or 9router config found.")
        }
    }

    private static func readFile(_ file: URL, into context: inout Context) throws {
        let name = file.lastPathComponent
        let ext = file.pathExtension.lowercased()
        context.fileCount += 1

        switch true {
        case name == "data.sqlite" || ext == "sqlite" || ext == "db":
            try NineRouterConfig.readDatabase(file, into: &context)
        case name == "db.json":
            try NineRouterConfig.readLegacyJSON(try Data(contentsOf: file), into: &context)
        case name == "auth.json":
            try OpencodeConfig.readAuth(try Data(contentsOf: file), into: &context)
        case ext == "json" || ext == "jsonc":
            try OpencodeConfig.readConfig(try Data(contentsOf: file), fileName: name, into: &context)
        case name == ".credentials.yaml":
            try DeepSeekHarnessConfig.readCredentials(try String(contentsOf: file, encoding: .utf8), into: &context)
        case ext == "yaml" || ext == "yml":
            try DeepSeekHarnessConfig.readSettings(try String(contentsOf: file, encoding: .utf8), fileName: name,
                                                   into: &context)
        case name == ".env" || ext == "env":
            context.environment.merge(DotEnv.parse(try String(contentsOf: file, encoding: .utf8))) { _, new in new }
        default:
            context.fileCount -= 1
            context.notes.append("\(name): not a config Spark knows how to import.")
        }
    }
}

// MARK: - Shared state

extension ProviderImporter {
    /// How a provider's API key is found once every picked file has been read.
    enum KeyReference: Sendable {
        case none
        case literal(String)
        /// An environment variable, from the picked `.env`/credentials files or Spark's own environment.
        case environment(String)
        /// An entry in opencode's `auth.json`, by opencode provider ID.
        case opencodeAuth(String)
    }

    struct Draft {
        /// The provider's ID in the source tool's config (e.g. `openrouter`).
        var sourceKey: String
        var config: CustomProviderConfig
        var key: KeyReference
        /// Tried when `key` doesn't resolve (e.g. a provider's conventional `*_API_KEY` variable).
        var fallbackKey: KeyReference = .none
        /// Found only as a saved key for a well-known provider, not as a configured provider.
        var isKeyOnly = false
    }

    struct Context {
        var drafts: [Draft] = []
        var notes: [String] = []
        var fileCount = 0
        /// Variables from picked `.env` files and DeepSeek Harness credentials.
        var environment: [String: String] = [:]
        /// Keys from opencode's `auth.json`, by opencode provider ID.
        var opencodeAuth: [String: String] = [:]
        /// Keys from DeepSeek Harness credentials that are filed under a provider ID.
        var credentialsByProvider: [String: String] = [:]

        mutating func add(_ draft: Draft) {
            drafts.removeAll { $0.config.id == draft.config.id }
            drafts.append(draft)
        }

        func resolve(_ reference: KeyReference) -> String? {
            let value: String? = switch reference {
            case .none: nil
            case .literal(let key): key
            case .environment(let name): environment[name] ?? ProcessInfo.processInfo.environment[name]
            case .opencodeAuth(let id): opencodeAuth[id]
            }
            return value.flatMap { $0.isEmpty ? nil : $0 }
        }

        func finish() -> ProviderImportReport {
            var report = ProviderImportReport(notes: notes)
            for draft in drafts {
                let key = resolve(draft.key) ?? resolve(draft.fallbackKey)
                    ?? credentialsByProvider[draft.sourceKey]
                report.providers.append(ImportedProvider(config: draft.config, apiKey: key,
                                                         replacesExisting: !draft.isKeyOnly))
                if key == nil, case .environment(let name) = draft.key {
                    report.notes.append("\(draft.config.name): add its API key in Settings (it reads \(name), which Spark can't see).")
                }
            }
            // opencode keys whose provider wasn't in the picked config: may match an earlier import.
            let imported = Set(drafts.map(\.config.id))
            for (id, key) in opencodeAuth where !imported.contains(OpencodeConfig.providerID(id)) {
                report.keys[OpencodeConfig.providerID(id)] = key
            }
            return report
        }
    }
}

/// Well-known OpenAI-compatible endpoints, for configs that name a built-in provider without a URL.
enum KnownEndpoint {
    struct Endpoint {
        let name: String
        let baseURL: URL
        let keyVariable: String
    }

    static func named(_ id: String) -> Endpoint? {
        let endpoint: (String, String, String)? = switch id.lowercased() {
        case "openai": ("OpenAI", "https://api.openai.com/v1", "OPENAI_API_KEY")
        case "openrouter": ("OpenRouter", "https://openrouter.ai/api/v1", "OPENROUTER_API_KEY")
        case "deepseek", "deepseek-official": ("DeepSeek", "https://api.deepseek.com/v1", "DEEPSEEK_API_KEY")
        case "groq": ("Groq", "https://api.groq.com/openai/v1", "GROQ_API_KEY")
        case "mistral": ("Mistral", "https://api.mistral.ai/v1", "MISTRAL_API_KEY")
        case "xai": ("xAI", "https://api.x.ai/v1", "XAI_API_KEY")
        case "moonshotai", "moonshot": ("Moonshot AI", "https://api.moonshot.ai/v1", "MOONSHOT_API_KEY")
        case "zai", "zhipuai": ("Z.ai", "https://api.z.ai/api/paas/v4", "ZAI_API_KEY")
        default: nil
        }
        guard let endpoint, let url = URL(string: endpoint.1) else { return nil }
        return Endpoint(name: endpoint.0, baseURL: url, keyVariable: endpoint.2)
    }

    /// Providers whose native API Spark can't talk to yet (it only speaks OpenAI Chat Completions).
    static func isUnsupported(_ id: String) -> Bool {
        let lowered = id.lowercased()
        return ["anthropic", "google", "vertex", "bedrock", "azure"].contains { lowered.contains($0) }
    }

    /// A usable API root from a config value: must be http(s) with a host.
    static func baseURL(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string), url.scheme == "http" || url.scheme == "https", url.host() != nil
        else { return nil }
        return url
    }
}

/// `KEY=value` lines, as in a `.env` file.
enum DotEnv {
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line.removeFirst("export ".count) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            if !name.isEmpty { values[name] = value }
        }
        return values
    }
}
