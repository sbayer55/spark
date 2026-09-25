import Foundation
import Observation

/// Every open chat, most recently used first; the first one is shown in the panel.
/// Also holds the state of the ⌃Tab switcher.
@MainActor
@Observable
final class ChatStore {
    let registry: ProviderRegistry
    /// App-wide Brave Search key (Keychain-backed); shared by every chat and the Settings window.
    let braveKey: BraveSearchKey

    /// Never empty. Kept in most-recently-used order, so `chats[0]` is the active chat.
    private(set) var chats: [ChatViewModel]

    /// The switcher row highlighted (an index into `chats`), or `nil` while the switcher is closed.
    private(set) var switcherIndex: Int?

    /// Incremented to ask the input field to take focus (e.g. when the panel opens or the chat changes).
    private(set) var focusRequest = 0

    var active: ChatViewModel { chats[0] }
    var isSwitcherOpen: Bool { switcherIndex != nil }

    init(registry: ProviderRegistry = ProviderRegistry(), braveKey: BraveSearchKey = BraveSearchKey()) {
        self.registry = registry
        self.braveKey = braveKey
        let first = ChatViewModel(registry: registry, braveKey: braveKey, preferredSelection: ModelPreference.stored)
        first.isActive = true
        chats = [first]
    }

    /// Shows `chat`, moving it to the front. The chat being left is dropped if it's empty.
    func activate(_ chat: ChatViewModel) {
        switcherIndex = nil
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
            requestFocus()
            return
        }
        activate(makeChat())
    }

    /// Closes the shown chat, stopping its reply, and shows the most recently used other chat.
    func closeActiveChat() {
        switcherIndex = nil
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
        return ChatViewModel(registry: registry, braveKey: braveKey,
                             preferredSelection: template.preferredSelection ?? ModelPreference.stored)
    }
}
