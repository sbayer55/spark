import AppKit

/// Borderless, non-activating floating panel that hosts the chat UI (Spotlight-style).
final class ChatPanel: NSPanel {
    /// Called when Escape is pressed. The owner decides whether to cancel a stream or close.
    var onEscape: (() -> Void)?
    /// Called for ⌘= / ⌘+ (larger), ⌘- (smaller), and ⌘0 (reset).
    var onTextSize: ((TextSize.Command) -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        // Fully transparent window; Liquid Glass in the SwiftUI content provides the visuals.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    // Borderless panels refuse key status by default; we need it for text input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Intercept Escape before the text view turns it into autocomplete,
        // unless an input method is mid-composition and needs it.
        if event.type == .keyDown, event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           !((firstResponder as? NSTextView)?.hasMarkedText() ?? false) {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    // Handled here rather than as menu commands: the panel is non-activating, so the
    // app's main menu doesn't reliably receive key equivalents while the panel is key.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        if modifiers == .command, let onTextSize {
            switch event.charactersIgnoringModifiers {
            case "=", "+": onTextSize(.increase); return true
            case "-": onTextSize(.decrease); return true
            case "0": onTextSize(.reset); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
