import Foundation
import Observation

/// Amazon Bedrock's settings: region and sign-in method in `UserDefaults`, credentials in the Keychain
/// (one item, so an ad-hoc-signed build asks for Keychain access once rather than per field).
@MainActor
@Observable
final class BedrockSettings {
    enum Auth: String, CaseIterable, Identifiable {
        /// A Bedrock API key, sent as a bearer token.
        case apiKey
        /// An IAM access key, used to sign requests (SigV4).
        case accessKeys

        var id: Self { self }

        var label: String {
            switch self {
            case .apiKey: "API key"
            case .accessKeys: "Access keys"
            }
        }
    }

    struct Secrets: Codable, Equatable {
        var apiKey = ""
        var accessKeyID = ""
        var secretAccessKey = ""
        /// Only for temporary credentials.
        var sessionToken = ""
    }

    static let defaultRegion = "us-east-1"
    static let regionKey = "bedrockRegion"
    static let authKey = "bedrockAuth"
    private static let keychainAccount = "bedrock-credentials"

    var region: String {
        didSet { UserDefaults.standard.set(region, forKey: Self.regionKey) }
    }

    var auth: Auth {
        didSet { UserDefaults.standard.set(auth.rawValue, forKey: Self.authKey) }
    }

    /// Bound field by field in Settings; every change writes through to the Keychain.
    var secrets: Secrets {
        didSet {
            guard secrets != oldValue else { return }
            let data = secrets == Secrets() ? nil : try? JSONEncoder().encode(secrets)
            try? Keychain.set(data.map { String(decoding: $0, as: UTF8.self) }, account: Self.keychainAccount)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        region = defaults.string(forKey: Self.regionKey) ?? Self.defaultRegion
        auth = defaults.string(forKey: Self.authKey).flatMap(Auth.init) ?? .apiKey
        let stored = (try? Keychain.string(account: Self.keychainAccount)).map { Data($0.utf8) }
        secrets = stored.flatMap { try? JSONDecoder().decode(Secrets.self, from: $0) } ?? Secrets()
        ConfigFile.onReload { [weak self] in self?.reload() }
    }

    /// Picks up an edit to the config file. Only differing values are set, so nothing is written back.
    private func reload() {
        let defaults = UserDefaults.standard
        let region = defaults.string(forKey: Self.regionKey) ?? Self.defaultRegion
        let auth = defaults.string(forKey: Self.authKey).flatMap(Auth.init) ?? .apiKey
        if self.region != region { self.region = region }
        if self.auth != auth { self.auth = auth }
    }

    /// The provider, or nil until the chosen sign-in method's credentials are filled in.
    /// An invalid region still yields a provider (which refuses to connect), so the model picker can say what's wrong.
    var provider: BedrockProvider? {
        let credentials: BedrockProvider.Credentials
        switch auth {
        case .apiKey:
            let key = Self.trimmed(secrets.apiKey)
            guard !key.isEmpty else { return nil }
            credentials = .apiKey(key)
        case .accessKeys:
            let id = Self.trimmed(secrets.accessKeyID)
            let secret = Self.trimmed(secrets.secretAccessKey)
            guard !id.isEmpty, !secret.isEmpty else { return nil }
            let token = Self.trimmed(secrets.sessionToken)
            credentials = .accessKeys(AWSCredentials(accessKeyID: id, secretAccessKey: secret,
                                                     sessionToken: token.isEmpty ? nil : token))
        }
        let region = Self.trimmed(region).lowercased()
        return BedrockProvider(region: region.isEmpty ? Self.defaultRegion : region, credentials: credentials)
    }

    private static func trimmed(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
