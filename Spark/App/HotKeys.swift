import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that shows/hides the chat panel. Default: Option+Space.
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}
