import Foundation
import Observation
import Security
import Synchronization

/// Generic-password items in the user's login keychain, keyed by this app's bundle identifier.
///
/// Works under App Sandbox with no extra entitlements. Deliberately avoids
/// `kSecUseDataProtectionKeychain`, which needs an application-identifier entitlement that
/// ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) doesn't provide. One consequence of ad-hoc signing:
/// each rebuild has a new code signature, so macOS may ask once per build whether Spark may use
/// the item; "Always Allow" silences it until the next rebuild.
///
/// With `LaunchOptions.ephemeralSecrets` on, items live in memory for the launch instead, and the Keychain
/// is never touched. An item not yet set that launch reads from the environment variable `SPARK_SECRET_`
/// + the account name uppercased with non-alphanumerics as `_`, e.g. `SPARK_SECRET_ANTHROPIC_API_KEY`,
/// `SPARK_SECRET_BRAVE_SEARCH_API_KEY`, or `SPARK_SECRET_BEDROCK_CREDENTIALS` (JSON: `{"apiKey": "…"}`).
enum Keychain {
    struct Failure: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
        }
    }

    private static let service = Bundle.main.bundleIdentifier ?? "com.tesseraga.spark"

    /// Items set this launch in ephemeral mode, by account. An empty string records a deletion, so the
    /// environment variable doesn't bring a removed item back.
    private static let ephemeralItems = Mutex<[String: String]>([:])

    /// The stored string, or nil if there is no item for `account`.
    static func string(account: String) throws -> String? {
        if LaunchOptions.ephemeralSecrets {
            let value = ephemeralItems.withLock { $0[account] }
                ?? ProcessInfo.processInfo.environment[environmentVariable(for: account)]
            return value?.isEmpty == false ? value : nil
        }

        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }

    /// Stores `value` for `account`; nil or empty removes the item.
    static func set(_ value: String?, account: String) throws {
        if LaunchOptions.ephemeralSecrets {
            ephemeralItems.withLock { $0[account] = value ?? "" }
            return
        }

        let query = baseQuery(account: account)
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
            return
        }

        let data = Data(value.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData] = data
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    /// `SPARK_SECRET_` + `account` uppercased, with anything but ASCII letters and digits as `_`.
    static func environmentVariable(for account: String) -> String {
        "SPARK_SECRET_" + String(account.uppercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
    }

    private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}

/// One secret (e.g. an API key) stored in the Keychain and mirrored in memory, so views and the
/// provider registry stay in sync through Observation.
@MainActor
@Observable
final class KeychainSecret {
    let account: String

    private(set) var value: String

    var hasValue: Bool { !value.isEmpty }

    /// Bound by Settings; every set writes through to the Keychain.
    var text: String {
        get { value }
        set {
            value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            try? Keychain.set(value, account: account)
        }
    }

    init(account: String) {
        self.account = account
        value = (try? Keychain.string(account: account)) ?? ""
    }
}
