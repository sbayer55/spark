import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    let registry: ProviderRegistry

    var messages: [ChatMessage] = []
    var draft = ""
    private(set) var selection: ModelSelection?

    /// Incremented to ask the input field to take focus (e.g. when the panel opens).
    private(set) var focusRequest = 0

    /// The assistant message currently being streamed, if any.
    private(set) var streamingMessageID: UUID?
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    var isStreaming: Bool { streamingMessageID != nil }

    var canSend: Bool {
        !isStreaming && selection != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The model the user last picked explicitly; restored whenever it's available.
    @ObservationIgnored private var preferredSelection: ModelSelection? {
        get {
            let defaults = UserDefaults.standard
            guard let provider = defaults.string(forKey: Self.providerKey),
                  let model = defaults.string(forKey: Self.modelKey) else { return nil }
            return ModelSelection(providerID: provider, model: model)
        }
        set {
            UserDefaults.standard.set(newValue?.providerID, forKey: Self.providerKey)
            UserDefaults.standard.set(newValue?.model, forKey: Self.modelKey)
        }
    }

    private static let providerKey = "selectedProviderID"
    private static let modelKey = "selectedModel"

    init(registry: ProviderRegistry = ProviderRegistry()) {
        self.registry = registry
        self.selection = preferredSelection
    }

    func select(_ selection: ModelSelection) {
        self.selection = selection
        preferredSelection = selection
    }

    /// Reloads provider model lists, then restores the preferred model or falls back to a default.
    func refreshModels() async {
        await registry.refresh()
        if let preferred = preferredSelection, registry.contains(preferred) {
            selection = preferred
        } else if preferredSelection == nil || !(selection.map(registry.contains) ?? false) {
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
                await self?.refreshModels()
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

    func newChat() {
        cancelStreaming()
        messages.removeAll()
        draft = ""
        requestFocus()
    }

    func requestFocus() {
        focusRequest &+= 1
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
    }
}
