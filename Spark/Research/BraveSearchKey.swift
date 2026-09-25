import Foundation
import Observation

/// The Brave Search API key: stored in the Keychain and mirrored in memory so the composer's
/// Research toggle and the Settings field stay in sync through Observation.
@MainActor
@Observable
final class BraveSearchKey {
    static let account = "brave-search-api-key"

    private(set) var value: String

    var hasKey: Bool { !value.isEmpty }

    /// Bound by Settings; every set writes through to the Keychain.
    var key: String {
        get { value }
        set {
            value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            try? Keychain.set(value, account: Self.account)
        }
    }

    init() {
        value = (try? Keychain.string(account: Self.account)) ?? ""
    }
}
