import Foundation

/// How long a chat survives while the panel is closed before reopening starts a new one.
/// Stored in `UserDefaults` as whole minutes; `forever` keeps the chat until the user starts a new one.
enum ChatRetention {
    static let key = "chatRetentionMinutes"
    static let defaultMinutes = 5
    static let forever = -1

    static let options: [(minutes: Int, label: String)] = [
        (0, "Don't keep"),
        (1, "1 minute"),
        (5, "5 minutes"),
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 hour"),
        (forever, "Until I start a new chat"),
    ]

    /// Whether a chat whose panel has been closed for `elapsed` should be replaced by a new one.
    static func hasExpired(closedFor elapsed: Duration, defaults: UserDefaults = .standard) -> Bool {
        // `integer(forKey:)` also parses strings, as launch arguments (`-chatRetentionMinutes 0`) arrive.
        let minutes = defaults.object(forKey: key) == nil ? defaultMinutes : defaults.integer(forKey: key)
        guard minutes != forever else { return false }
        return elapsed >= .seconds(minutes * 60)
    }
}

extension ChatRetention {
    /// When the panel was last hidden, kept across launches so restored chats honor the retention setting too.
    static let panelHiddenAtKey = "panelHiddenAt"

    static func recordPanelHidden(at date: Date = .now, defaults: UserDefaults = .standard) {
        guard !LaunchOptions.ephemeralHistory else { return }
        defaults.set(date, forKey: panelHiddenAtKey)
    }

    static func recordPanelShown(defaults: UserDefaults = .standard) {
        guard !LaunchOptions.ephemeralHistory else { return }
        defaults.removeObject(forKey: panelHiddenAtKey)
    }

    /// Whether the chats open when the panel was last hidden (possibly in an earlier launch) should be dropped.
    /// With no record of a hide (first launch, or the app quit with the panel showing) they're kept.
    static func hasExpiredSincePanelHidden(defaults: UserDefaults = .standard) -> Bool {
        guard let hiddenAt = defaults.object(forKey: panelHiddenAtKey) as? Date else { return false }
        return hasExpired(closedFor: .seconds(max(0, Date.now.timeIntervalSince(hiddenAt))), defaults: defaults)
    }
}
