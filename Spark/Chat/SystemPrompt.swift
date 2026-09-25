import Foundation

/// The user's system prompt (Settings → General), persisted in `UserDefaults`. Empty means none.
/// Read at each send, so an edit applies to the next message in every chat.
enum SystemPrompt {
    static let key = "systemPrompt"

    /// The prompt, or nil when it's blank.
    static func current(defaults: UserDefaults = .standard) -> String? {
        let prompt = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return prompt.isEmpty ? nil : prompt
    }
}
