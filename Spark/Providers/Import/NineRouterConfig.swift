import Foundation
import SQLite3

/// 9router's local data folder (`~/.9router`): an SQLite database (`db/data.sqlite`), or `db.json` in
/// older versions. Spark talks to the router itself (`http://localhost:20128/v1`) with one of its API keys;
/// the upstream providers configured inside 9router stay there.
enum NineRouterConfig {
    static let providerID = "\(ProviderConfigSource.nineRouter.rawValue).local"
    static let defaultPort = 20128

    static func readDatabase(_ file: URL, into context: inout ProviderImporter.Context) throws {
        // Read-only and immutable: no journal or lock files, which the sandbox wouldn't let us create.
        var components = URLComponents(url: file, resolvingAgainstBaseURL: false)
        components?.scheme = "file"
        components?.queryItems = [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components?.string else { throw ProviderImportError("Invalid database path.") }

        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            throw ProviderImportError("Couldn't open the 9router database.")
        }

        let apiKey = firstString(in: database, sql: """
            SELECT key FROM apiKeys WHERE isActive = 1 ORDER BY createdAt LIMIT 1
            """)
        let settings = firstString(in: database, sql: "SELECT data FROM settings WHERE id = 1")
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        add(apiKey: apiKey, settings: settings, into: &context)
    }

    /// Pre-SQLite layout: `{ "apiKeys": [{ "key": …, "isActive": true }], "settings": { … } }`.
    static func readLegacyJSON(_ data: Data, into context: inout ProviderImporter.Context) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderImportError("Not a 9router database.")
        }
        let keys = root["apiKeys"] as? [[String: Any]] ?? []
        let apiKey = keys.first { $0["isActive"] as? Bool ?? true }?["key"] as? String
        add(apiKey: apiKey, settings: root["settings"] as? [String: Any], into: &context)
    }

    private static func add(apiKey: String?, settings: [String: Any]?, into context: inout ProviderImporter.Context) {
        let port = settings?["port"] as? Int ?? defaultPort
        guard let baseURL = URL(string: "http://localhost:\(port)/v1") else { return }
        if apiKey == nil {
            context.notes.append("9router: no active API key found; create one in the 9router dashboard, then add it in Settings.")
        }
        // Models come live from the router (`GET /models`), so combos and newly connected providers show up.
        context.add(ProviderImporter.Draft(
            sourceKey: "local",
            config: CustomProviderConfig(id: providerID, name: "9router", baseURL: baseURL, models: [],
                                         source: .nineRouter),
            key: apiKey.map { .literal($0) } ?? .none
        ))
    }

    private static func firstString(in database: OpaquePointer?, sql: String) -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: text)
    }
}
