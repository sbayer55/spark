import Foundation
import Observation

/// Every open chat, most recently used first; the first one is shown in the panel.
/// Also holds the state of the ⌃Tab switcher and the ⌘K history list.
@MainActor
@Observable
final class ChatStore {
    let registry: ProviderRegistry
    /// App-wide Brave Search key (Keychain-backed); shared by every chat and the Settings window.
    let braveKey: BraveSearchKey
    /// Saved chats; every chat writes itself here as it changes.
    let archive: ChatArchive

    /// `UserDefaults` key for the IDs of the open chats, most recently used first, to reopen them at the next launch.
    private static let openChatIDsKey = "openChatIDs"

    /// Never empty. Kept in most-recently-used order, so `chats[0]` is the active chat.
    private(set) var chats: [ChatViewModel] {
        didSet { saveOpenChats() }
    }

    /// The switcher row highlighted (an index into `chats`), or `nil` while the switcher is closed.
    private(set) var switcherIndex: Int?

    /// Incremented to ask the input field to take focus (e.g. when the panel opens or the chat changes).
    private(set) var focusRequest = 0

    var active: ChatViewModel { chats[0] }
    var isSwitcherOpen: Bool { switcherIndex != nil }

    /// Whether the ⌘/ keyboard shortcuts overlay is showing.
    private(set) var isShowingShortcuts = false

    /// Whether the ⌘K history list is showing.
    private(set) var isHistoryOpen = false
    /// The history list's search text; typing resets the highlight to the first match.
    var historyQuery = "" {
        didSet { historyIndex = 0 }
    }
    /// The highlighted row of `historyResults`.
    private(set) var historyIndex = 0

    init(registry: ProviderRegistry = ProviderRegistry(), braveKey: BraveSearchKey = BraveSearchKey(),
         archive: ChatArchive = ChatArchive()) {
        self.registry = registry
        self.braveKey = braveKey
        self.archive = archive

        // The chats open at the last quit come back, unless the panel has been closed longer than the
        // retention setting allows (then they stay in history only) or history isn't being saved.
        var restored: [ChatViewModel] = []
        if archive.isEnabled, !ChatRetention.hasExpiredSincePanelHidden() {
            let ids = UserDefaults.standard.stringArray(forKey: Self.openChatIDsKey) ?? []
            restored = ids.compactMap(UUID.init).compactMap(archive.record).map {
                ChatViewModel(record: $0, registry: registry, braveKey: braveKey, archive: archive)
            }
        }
        if restored.isEmpty {
            restored = [ChatViewModel(registry: registry, braveKey: braveKey, archive: archive,
                                      preferredSelection: ModelPreference.stored)]
        }
        restored[0].isActive = true
        chats = restored
        // Property observers don't run in init; chats that failed to restore are dropped from the list here.
        saveOpenChats()
    }

    /// Shows `chat`, moving it to the front. The chat being left is dropped if it's empty.
    func activate(_ chat: ChatViewModel) {
        switcherIndex = nil
        isHistoryOpen = false
        defer { requestFocus() }
        guard chat !== active else { return }

        let previous = active
        previous.isActive = false
        chats.removeAll { $0 === chat }
        if previous.isEmpty {
            chats.removeAll { $0 === previous }
        }
        chats.insert(chat, at: 0)
        chat.isActive = true
    }

    /// Starts a chat with the current chat's model. The current chat stays open in the switcher.
    func newChat() {
        guard !active.isEmpty else {
            switcherIndex = nil
            isHistoryOpen = false
            requestFocus()
            return
        }
        activate(makeChat())
    }

    /// Closes the shown chat, stopping its reply, and shows the most recently used other chat.
    /// The closed chat stays in history.
    func closeActiveChat() {
        switcherIndex = nil
        isHistoryOpen = false
        let closing = chats.removeFirst()
        closing.cancelStreaming()
        closing.isActive = false
        if chats.isEmpty {
            chats.append(makeChat(like: closing))
        }
        active.isActive = true
        requestFocus()
    }

    /// Drops every chat that isn't mid-reply, after the panel was closed longer than the retention setting allows.
    /// A new chat is shown unless the shown chat is still replying.
    func discardIdleChats() {
        switcherIndex = nil
        let current = active
        chats.removeAll { !$0.isStreaming }
        if chats.first !== current {
            current.isActive = false
            chats.insert(makeChat(like: current), at: 0)
            active.isActive = true
        }
    }

    // MARK: - Switcher

    /// ⌃Tab (⌃⇧Tab backward): opens the switcher on the previous chat, or moves the highlight while it's open.
    func cycleSwitcher(backward: Bool) {
        guard chats.count > 1 else { return }
        if isSwitcherOpen {
            moveSwitcherHighlight(by: backward ? -1 : 1)
        } else {
            isShowingShortcuts = false
            isHistoryOpen = false
            switcherIndex = backward ? chats.count - 1 : 1
        }
    }

    /// Moves the highlight, wrapping around at either end.
    func moveSwitcherHighlight(by offset: Int) {
        guard let switcherIndex else { return }
        let count = chats.count
        self.switcherIndex = ((switcherIndex + offset) % count + count) % count
    }

    /// Shows the highlighted chat and closes the switcher.
    func commitSwitcher() {
        guard let switcherIndex, chats.indices.contains(switcherIndex) else {
            cancelSwitcher()
            return
        }
        activate(chats[switcherIndex])
    }

    func cancelSwitcher() {
        switcherIndex = nil
    }

    // MARK: - Shortcuts overlay

    func toggleShortcuts() {
        switcherIndex = nil
        isHistoryOpen = false
        isShowingShortcuts.toggle()
    }

    func showShortcuts() {
        switcherIndex = nil
        isHistoryOpen = false
        isShowingShortcuts = true
    }

    func dismissShortcuts() {
        isShowingShortcuts = false
    }

    // MARK: - History

    /// Saved chats matching the search text (all of them while it's empty), newest first.
    var historyResults: [ChatRecord] {
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return archive.records }
        return archive.records.filter { $0.matches(query) }
    }

    /// Whether a saved chat is one of the open ones.
    func isOpen(_ record: ChatRecord) -> Bool {
        chats.contains { $0.id == record.id }
    }

    func toggleHistory() {
        if isHistoryOpen { dismissHistory() } else { showHistory() }
    }

    /// Opens the ⌘K list with an empty search; the list's field takes the keyboard.
    func showHistory() {
        switcherIndex = nil
        isShowingShortcuts = false
        historyQuery = ""
        isHistoryOpen = true
    }

    func dismissHistory() {
        guard isHistoryOpen else { return }
        isHistoryOpen = false
        requestFocus()
    }

    /// Moves the highlight, wrapping around at either end.
    func moveHistoryHighlight(by offset: Int) {
        let count = historyResults.count
        guard count > 0 else { return }
        historyIndex = ((historyIndex + offset) % count + count) % count
    }

    /// Opens the highlighted chat and closes the list.
    func commitHistory() {
        let results = historyResults
        guard results.indices.contains(historyIndex) else { return }
        open(results[historyIndex])
    }

    /// Shows a saved chat: the open one if it's still open, else reopened from history.
    func open(_ record: ChatRecord) {
        if let chat = chats.first(where: { $0.id == record.id }) {
            activate(chat)
        } else {
            activate(ChatViewModel(record: record, registry: registry, braveKey: braveKey, archive: archive))
        }
    }

    /// Deletes a saved chat. An open copy stays open (and is saved again if it changes).
    func deleteFromHistory(_ record: ChatRecord) {
        archive.delete(id: record.id)
        historyIndex = min(historyIndex, max(0, historyResults.count - 1))
    }

    // MARK: -

    /// Reloads provider model lists, then restores each chat's preferred model or falls back to a default.
    func refreshModels() async {
        await registry.refresh()
        for chat in chats {
            chat.reconcileSelection()
        }
    }

    func requestFocus() {
        focusRequest &+= 1
    }

    private func makeChat(like chat: ChatViewModel? = nil) -> ChatViewModel {
        let template = chat ?? active
        return ChatViewModel(registry: registry, braveKey: braveKey, archive: archive,
                             preferredSelection: template.preferredSelection ?? ModelPreference.stored)
    }

    /// Remembers which chats are open, so they can be reopened at the next launch.
    private func saveOpenChats() {
        guard !LaunchOptions.ephemeralHistory else { return }
        UserDefaults.standard.set(chats.map(\.id.uuidString), forKey: Self.openChatIDsKey)
    }
}
