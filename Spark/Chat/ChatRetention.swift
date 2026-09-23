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
        let minutes = defaults.object(forKey: key) as? Int ?? defaultMinutes
        guard minutes != forever else { return false }
        return elapsed >= .seconds(minutes * 60)
    }
}
