import Foundation
import Observation

/// One chat: its transcript, draft, model, and in-flight reply. `ChatStore` holds every open chat.
@MainActor
@Observable
final class ChatViewModel: Identifiable {
    let id = UUID()
    let registry: ProviderRegistry

    var messages: [ChatMessage] = []
    var draft = ""
    private(set) var selection: ModelSelection?
    /// The model this chat prefers (picked here, or inherited when it was created); restored whenever it's available.
    private(set) var preferredSelection: ModelSelection?

    /// Set by `ChatStore` on the chat shown in the panel.
    var isActive = false {
        didSet { if isActive { hasUnreadReply = false } }
    }
    /// A reply finished while this chat wasn't showing.
    private(set) var hasUnreadReply = false

    /// The assistant message currently being streamed, if any.
    private(set) var streamingMessageID: UUID?
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    var isStreaming: Bool { streamingMessageID != nil }

    var canSend: Bool {
        !isStreaming && selection != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Nothing sent and nothing typed; such a chat is dropped once the user moves away from it.
    var isEmpty: Bool {
        messages.isEmpty && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The first line of the first message, or "New Chat".
    var title: String {
        let first = messages.first { $0.role == .user }?.content
            .split(whereSeparator: \.isNewline).first
        return first.map(String.init) ?? "New Chat"
    }

    init(registry: ProviderRegistry, preferredSelection: ModelSelection?) {
        self.registry = registry
        self.preferredSelection = preferredSelection
        self.selection = preferredSelection
    }

    func select(_ selection: ModelSelection) {
        self.selection = selection
        preferredSelection = selection
        ModelPreference.stored = selection
    }

    /// Restores the preferred model if it's available, else falls back to a default when the current one isn't.
    func reconcileSelection() {
        if let preferredSelection, registry.contains(preferredSelection) {
            selection = preferredSelection
        } else if !(selection.map(registry.contains) ?? false) {
            selection = registry.defaultSelection
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming,
              let selection, let provider = registry.provider(id: selection.providerID)
        else { return }

        draft = ""
        messages.append(ChatMessage(role: .user, content: text))
        let history = messages

        let reply = ChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(reply)
        streamingMessageID = reply.id

        streamTask = Task { [weak self] in
            do {
                for try await chunk in provider.stream(messages: history, model: selection.model) {
                    self?.append(chunk, to: reply.id)
                }
                self?.finish(reply.id, status: Task.isCancelled ? .cancelled : .complete)
            } catch is CancellationError {
                self?.finish(reply.id, status: .cancelled)
            } catch {
                self?.finish(reply.id, status: .failed(error.localizedDescription))
                // The provider may have gone away; update availability (and the menu bar icon) now.
                await self?.registry.refresh()
                self?.reconcileSelection()
            }
        }
    }

    /// Stops the in-flight response, if any. Returns whether anything was cancelled.
    @discardableResult
    func cancelStreaming() -> Bool {
        guard let id = streamingMessageID else { return false }
        streamTask?.cancel()
        streamTask = nil
        finish(id, status: .cancelled)
        return true
    }

    private func append(_ chunk: String, to id: UUID) {
        guard streamingMessageID == id, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += chunk
    }

    private func finish(_ id: UUID, status: ChatMessage.Status) {
        guard streamingMessageID == id else { return }
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].status = status
        }
        streamingMessageID = nil
        streamTask = nil
        if !isActive && status != .cancelled {
            hasUnreadReply = true
        }
    }
}

/// The model the user last picked in any chat; new chats start with it when there's no current chat to copy.
enum ModelPreference {
    private static let providerKey = "selectedProviderID"
    private static let modelKey = "selectedModel"

    static var stored: ModelSelection? {
        get {
            let defaults = UserDefaults.standard
            guard let provider = defaults.string(forKey: providerKey),
                  let model = defaults.string(forKey: modelKey) else { return nil }
            return ModelSelection(providerID: provider, model: model)
        }
        set {
            UserDefaults.standard.set(newValue?.providerID, forKey: providerKey)
            UserDefaults.standard.set(newValue?.model, forKey: modelKey)
        }
    }
}
