import Foundation
import Security

/// Generic-password items in the user's login keychain, keyed by this app's bundle identifier.
///
/// Works under App Sandbox with no extra entitlements. Deliberately avoids
/// `kSecUseDataProtectionKeychain`, which needs an application-identifier entitlement that
/// ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) doesn't provide. One consequence of ad-hoc signing:
/// each rebuild has a new code signature, so macOS may ask once per build whether Spark may use
/// the item; "Always Allow" silences it until the next rebuild.
enum Keychain {
    struct Failure: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
        }
    }

    private static let service = Bundle.main.bundleIdentifier ?? "com.tesseraga.spark"

    /// The stored string, or nil if there is no item for `account`.
    static func string(account: String) throws -> String? {
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

    private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
