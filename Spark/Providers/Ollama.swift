import Foundation

/// Ollama, via its OpenAI-compatible endpoint (`<server>/v1`).
enum Ollama {
    static let baseURLKey = "ollamaBaseURL"
    static let defaultBaseURL = "http://localhost:11434"

    /// The server URL from Settings, falling back to the default when unset or invalid.
    static var serverURL: URL {
        let stored = UserDefaults.standard.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: stored), url.scheme == "http" || url.scheme == "https", url.host() != nil {
            return url
        }
        return URL(string: defaultBaseURL)!
    }

    static func provider() -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            id: "ollama",
            displayName: "Ollama",
            baseURL: { serverURL.appending(path: "v1") }
        )
    }
}
