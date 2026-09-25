import Foundation
import Observation

/// Saved chats: one JSON file per chat under Application Support, mirrored in memory (newest first) for the
/// ⌘K history list. Chats are saved as they change and the open ones come back after a relaunch (see `ChatStore`).
/// With `LaunchOptions.ephemeralHistory` on, nothing is read or written and the list starts empty.
@MainActor
@Observable
final class ChatArchive {
    /// `UserDefaults` key for the "Save chat history" setting; on unless set to false.
    static let enabledKey = "chatHistoryEnabled"
    /// The oldest chats beyond this many are deleted as new ones are saved.
    static let maxRecords = 1000

    /// Every saved chat, most recently updated first.
    private(set) var records: [ChatRecord]

    private let disk: ChatArchiveDisk?

    init(directory: URL? = LaunchOptions.ephemeralHistory ? nil : ChatArchive.defaultDirectory) {
        disk = directory.map(ChatArchiveDisk.init)
        records = directory.map(ChatArchiveDisk.load) ?? []
    }

    /// `Application Support/Chats` inside the app's sandbox container.
    nonisolated static var defaultDirectory: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "Chats", directoryHint: .isDirectory)
    }

    /// The "Save chat history" setting.
    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey)
    }

    func record(id: UUID) -> ChatRecord? {
        records.first { $0.id == id }
    }

    /// Adds or updates `record`, and drops the oldest chats past `maxRecords`. Does nothing while saving is off.
    func save(_ record: ChatRecord) {
        guard isEnabled, !record.messages.isEmpty else { return }
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        let dropped = records.count > Self.maxRecords ? records[Self.maxRecords...].map(\.id) : []
        records.removeLast(dropped.count)

        guard let disk else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return }
        Task {
            await disk.write(data, id: record.id)
            for id in dropped {
                await disk.delete(id: id)
            }
        }
    }

    func delete(id: UUID) {
        records.removeAll { $0.id == id }
        Task { await disk?.delete(id: id) }
    }

    func clear() {
        records.removeAll()
        Task { await disk?.clear() }
    }
}

/// The archive's folder; an actor so writes and deletes for the same chat happen in order, off the main actor.
actor ChatArchiveDisk {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Every readable chat in `directory`, newest first. Files that don't decode are skipped.
    nonisolated static func load(from directory: URL) -> [ChatRecord] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                (try? Data(contentsOf: file)).flatMap { try? decoder.decode(ChatRecord.self, from: $0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func write(_ data: Data, id: UUID) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(for: id), options: .atomic)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: file(for: id))
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
