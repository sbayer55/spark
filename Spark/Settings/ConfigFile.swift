import Foundation
import KeyboardShortcuts

/// Settings persisted as JSON in the real `~/.config/spark/config.json`, the durable source of truth.
///
/// `UserDefaults` stays the live store every setting reads and writes (`@AppStorage`, `didSet` write-throughs,
/// argument-domain overrides), so this only syncs its persistent domain with the file:
/// - at launch, the file's values replace the stored ones (a key missing from the file is reset to its default);
///   with no file yet, the current values are written out;
/// - a change made in the app rewrites the file (debounced);
/// - an edit made to the file while the app runs is applied, then `didReload` is posted so `@Observable` settings
///   that only read `UserDefaults` at init catch up.
///
/// Session state (open chats, panel-hidden time) and launch flags stay out of the file; secrets stay in the Keychain.
/// The sandbox reaches the file through a home-relative temporary-exception entitlement (see `project.yml`).
@MainActor
final class ConfigFile {
    static let shared = ConfigFile()

    /// Posted after an external edit to the file has been applied to `UserDefaults`.
    static let didReload = Notification.Name("SparkConfigFileDidReload")

    let url: URL
    private var directory: URL { url.deletingLastPathComponent() }
    private let defaults = UserDefaults.standard

    /// The file's bytes as last read or written, so our own writes don't trigger a reload.
    private var lastData: Data?
    /// The file doesn't parse; it isn't overwritten until the user fixes it.
    private var fileIsInvalid = false
    /// Set while applying the file, so the resulting `UserDefaults` changes don't write it back.
    private var isApplying = false
    private var writeTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?

    private static let shortcutKey = "KeyboardShortcuts_" + KeyboardShortcuts.Name.togglePanel.rawValue
    /// `UserDefaults` values that are themselves JSON; the file embeds them as JSON rather than as strings or data.
    private static let dataJSONKeys: Set<String> = [CustomProviders.defaultsKey]
    private static let stringJSONKeys: Set<String> = [shortcutKey]

    /// Every key kept in the file.
    static let keys: [String] = [
        Theme.key, TextSize.key, ChatRetention.key, ChatArchive.enabledKey, SystemPrompt.key, Ollama.baseURLKey,
        PanelAppearance.transparencyKey, PanelAppearance.blurKey, PanelAppearance.blurEngineKey,
        PanelAppearance.blurRadiusKey, PanelLayout.widthKey, PanelLayout.heightKey,
        BedrockSettings.regionKey, BedrockSettings.authKey,
        CustomProviders.defaultsKey, ModelPreference.providerKey, ModelPreference.modelKey, shortcutKey,
    ] + GatewaySettings.Kind.bifrost.defaultsKeys + GatewaySettings.Kind.nineRouter.defaultsKeys

    private init() {
        url = Self.realHome
            .appending(path: ".config/spark", directoryHint: .isDirectory)
            .appending(path: "config.json", directoryHint: .notDirectory)
    }

    /// The user's home, not the sandbox container `NSHomeDirectory()` returns.
    private static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    }

    // MARK: Lifecycle

    /// Applies the file to `UserDefaults`, or writes it from `UserDefaults` if it doesn't exist yet.
    /// Call before anything reads a setting.
    func load() {
        guard !LaunchOptions.ephemeralConfig else { return }
        guard let data = try? Data(contentsOf: url) else {
            write()
            return
        }
        apply(data, live: false)
    }

    /// Starts writing app-side changes to the file and applying file-side changes to the app.
    func start() {
        guard !LaunchOptions.ephemeralConfig else { return }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.defaultsChanged() }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        watchDirectory()
        watchFile()
    }

    /// Runs `action` on the main actor after each external edit to the file has been applied.
    static func onReload(_ action: @escaping @MainActor @Sendable () -> Void) {
        NotificationCenter.default.addObserver(forName: didReload, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
    }

    // MARK: App → file

    private func defaultsChanged() {
        guard !isApplying else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        guard !fileIsInvalid, let data = snapshot(), data != lastData else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastData = data
        } catch {
            NSLog("Spark: couldn't write %@: %@", url.path, error.localizedDescription)
        }
    }

    /// The stored settings as pretty-printed JSON. Reads only the persistent domain, so launch arguments
    /// (e.g. `-themeID dark`) never reach the file.
    private func snapshot() -> Data? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let stored = defaults.persistentDomain(forName: bundleID) ?? [:]
        var object: [String: Any] = [:]
        for key in Self.keys {
            if let value = stored[key], let json = Self.jsonValue(value, key: key) {
                object[key] = json
            }
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        return data + Data("\n".utf8)
    }

    private static func jsonValue(_ value: Any, key: String) -> Any? {
        if dataJSONKeys.contains(key) {
            return (value as? Data).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        }
        if stringJSONKeys.contains(key), let string = value as? String {
            return try? JSONSerialization.jsonObject(with: Data(string.utf8))
        }
        return value is String || value is NSNumber ? value : nil
    }

    // MARK: File → app

    /// Applies the file's contents. `live` is false at launch, before the hotkey is registered and any
    /// setting has been read.
    private func apply(_ data: Data, live: Bool) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            NSLog("Spark: %@ isn't a valid JSON object; keeping the current settings", url.path)
            fileIsInvalid = true
            return
        }
        fileIsInvalid = false
        lastData = data
        isApplying = true
        defer { isApplying = false }

        let stored = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        for key in Self.keys {
            let value = object[key].flatMap { Self.defaultsValue($0, key: key) }
            if live, key == Self.shortcutKey {
                applyShortcut(value)
                continue
            }
            if let value {
                if (stored[key] as? NSObject)?.isEqual(value) != true {
                    defaults.set(value, forKey: key)
                }
            } else if stored[key] != nil {
                defaults.removeObject(forKey: key)
            }
        }
        if live {
            NotificationCenter.default.post(name: Self.didReload, object: nil)
        }
    }

    private static func defaultsValue(_ json: Any, key: String) -> Any? {
        if dataJSONKeys.contains(key) {
            guard json is [Any] || json is [String: Any] else { return nil }
            return try? JSONSerialization.data(withJSONObject: json)
        }
        if stringJSONKeys.contains(key), json is [String: Any] {
            return (try? JSONSerialization.data(withJSONObject: json)).map { String(decoding: $0, as: UTF8.self) }
        }
        return json is String || json is NSNumber ? json : nil
    }

    /// Changes the hotkey through KeyboardShortcuts, so it re-registers with the system.
    private func applyShortcut(_ value: Any?) {
        let name = KeyboardShortcuts.Name.togglePanel
        let current = defaults.object(forKey: Self.shortcutKey) as? NSObject
        if let value, current?.isEqual(value) == true { return }
        switch value {
        case let string as String:
            guard let shortcut = try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: Data(string.utf8))
            else { return }
            KeyboardShortcuts.setShortcut(shortcut, for: name)
        case let number as NSNumber where !number.boolValue:
            KeyboardShortcuts.setShortcut(nil, for: name)
        case nil where current != nil:
            KeyboardShortcuts.reset(name)
        default:
            break
        }
    }

    private func reload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            // Editors often touch the file several times per save.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            // A missing file (deleted, or mid-save) changes nothing; the next app-side change writes it again.
            guard let data = try? Data(contentsOf: url), data != lastData else { return }
            apply(data, live: true)
        }
    }

    // MARK: Watching

    /// Atomic saves replace the file, which shows up as a change to the directory.
    private func watchDirectory() {
        directoryWatcher = makeWatcher(for: directory, events: .write) { [weak self] in
            self?.watchFile()
            self?.reload()
        }
    }

    /// In-place saves only change the file. Re-attached whenever the directory changes, since an atomic save
    /// leaves this watching the old file.
    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = makeWatcher(for: url, events: [.write, .extend, .delete, .rename]) { [weak self] in
            self?.reload()
        }
    }

    private func makeWatcher(
        for url: URL, events: DispatchSource.FileSystemEvent, handler: @escaping @MainActor @Sendable () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { handler() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }
}
