import AppKit
import SwiftUI

/// Owns the chat panel and its chats, and handles show/hide/positioning/sizing.
@MainActor
final class PanelController {
    let store: ChatStore
    let layout: PanelLayout
    private let panel: ChatPanel

    /// When the panel was last hidden; `nil` while it's showing. Continuous clock, so time asleep counts.
    private var hiddenAt: ContinuousClock.Instant?

    /// The in-progress user resize: which edge or corner, and the frame and mouse location it started from.
    private var resizeStart: (position: NSCursor.FrameResizePosition, frame: NSRect, mouse: NSPoint)?

    init(store: ChatStore = ChatStore(), layout: PanelLayout = PanelLayout()) {
        self.store = store
        self.layout = layout
        panel = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: layout.width, height: layout.fixedHeight ?? 120))

        let hostingView = NSHostingView(rootView: ChatView(store: store, layout: layout) { [weak self] height in
            self?.resize(toContentHeight: height)
        })
        hostingView.sizingOptions = []

        let resizeOverlay = PanelResizeOverlay(inset: PanelMetrics.inset)
        resizeOverlay.onBegin = { [weak self] position in self?.beginResize(from: position) }
        resizeOverlay.onDrag = { [weak self] in self?.continueResize() }
        resizeOverlay.onEnd = { [weak self] in self?.endResize() }

        let container = NSView(frame: panel.contentLayoutRect)
        for view in [hostingView, resizeOverlay] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        panel.contentView = container

        panel.onEscape = { [weak self] in self?.handleEscape() }
        panel.onTextSize = { TextSize.apply($0) }
        panel.onKeyEvent = { [weak self] event in self?.handleKey(event) ?? false }
        // ⌃ can be released elsewhere once the panel loses focus, so a switcher left open would get stuck.
        panel.onResignKey = { [weak self] in self?.store.cancelSwitcher() }

        applyThemeAppearance()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyThemeAppearance() }
        }
    }

    /// Matches the panel's appearance to the theme's light or dark background, so the glass, menus, and
    /// system controls agree with it. The system look (no theme) follows the system appearance.
    private func applyThemeAppearance() {
        let name: NSAppearance.Name? = Theme.current().map { $0.isDark ? .darkAqua : .aqua }
        guard panel.appearance?.name != name else { return }
        panel.appearance = name.flatMap(NSAppearance.init(named:))
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if !panel.isVisible {
            startNewChatIfExpired()
            position(on: activeScreen())
        }
        hiddenAt = nil
        panel.makeKeyAndOrderFront(nil)
        store.requestFocus()
        // Cheap local call; picks up models pulled or servers started since last open.
        Task { await store.refreshModels() }
    }

    func hide() {
        store.cancelSwitcher()
        panel.orderOut(nil)
        hiddenAt = .now
    }

    /// Drops the chats and starts a new one if the panel has been closed longer than the retention setting allows.
    /// Chats still streaming a reply are left alone.
    private func startNewChatIfExpired() {
        guard let hiddenAt, ChatRetention.hasExpired(closedFor: hiddenAt.duration(to: .now)) else { return }
        store.discardIdleChats()
    }

    /// Returns to the default width and content-driven height.
    func resetSize() {
        layout.reset()
        var frame = panel.frame
        frame.origin.x += (frame.width - layout.width) / 2
        frame.size.width = layout.width
        panel.setFrame(frame, display: true)
        // The content re-reports its natural height once it stops filling the fixed height.
    }

    private func handleEscape() {
        if !store.active.cancelStreaming() {
            hide()
        }
    }

    // MARK: - Chat keys

    /// ⌘N / ⌘W, and the ⌃Tab switcher: hold ⌃ and press Tab (⇧Tab backward) to move, release ⌃ to switch.
    /// While the switcher is open it takes every key: arrows move, Return switches, Escape cancels.
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if event.type == .flagsChanged {
            if store.isSwitcherOpen && !modifiers.contains(.control) {
                store.commitSwitcher()
            }
            return false
        }
        guard event.type == .keyDown else { return false }

        if event.keyCode == KeyCode.tab, modifiers.contains(.control) {
            store.cycleSwitcher(backward: modifiers.contains(.shift))
            return true
        }

        if store.isSwitcherOpen {
            switch event.keyCode {
            case KeyCode.upArrow: store.moveSwitcherHighlight(by: -1)
            case KeyCode.downArrow: store.moveSwitcherHighlight(by: 1)
            case KeyCode.return, KeyCode.keypadEnter: store.commitSwitcher()
            case KeyCode.escape: store.cancelSwitcher()
            default: break
            }
            return true
        }

        if modifiers == .command {
            switch event.charactersIgnoringModifiers {
            case "n": store.newChat(); return true
            case "w": store.closeActiveChat(); return true
            default: break
            }
        }
        return false
    }

    // MARK: - Layout

    /// Centers the panel horizontally with its top edge in the upper third of the screen.
    private func position(on screen: NSScreen?) {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        var size = panel.frame.size
        size.width = min(size.width, visible.width)
        size.height = min(size.height, visible.height)
        panel.setContentSize(size)
        let top = visible.maxY - visible.height / 6
        panel.setFrameTopLeftPoint(NSPoint(x: visible.midX - size.width / 2, y: top))
    }

    /// Grows or shrinks the panel to fit its content, keeping the top edge fixed.
    /// Does nothing once the user has chosen a height.
    private func resize(toContentHeight height: CGFloat) {
        let height = height.rounded(.up)
        guard !layout.isHeightFixed else { return }
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - User resizing

    private func beginResize(from position: NSCursor.FrameResizePosition) {
        resizeStart = (position, panel.frame, NSEvent.mouseLocation)
    }

    /// Applies the mouse's movement since `beginResize` to the dragged edges. Width-only drags leave
    /// the height to auto-sizing; any vertical drag hands the height to the user from then on.
    private func continueResize() {
        guard let start = resizeStart else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - start.mouse.x
        let dy = mouse.y - start.mouse.y
        let minSize = PanelMetrics.minSize
        var frame = panel.frame

        if start.position.movesRight {
            frame.origin.x = start.frame.minX
            frame.size.width = max(minSize.width, start.frame.width + dx)
        } else if start.position.movesLeft {
            frame.size.width = max(minSize.width, start.frame.width - dx)
            frame.origin.x = start.frame.maxX - frame.width
        }

        if start.position.movesBottom {
            frame.size.height = max(minSize.height, start.frame.height - dy)
            frame.origin.y = start.frame.maxY - frame.height
        } else if start.position.movesTop {
            frame.size.height = max(minSize.height, start.frame.height + dy)
            frame.origin.y = start.frame.minY
        }

        if start.position.movesTop || start.position.movesBottom {
            layout.fixedHeight = frame.height
        }
        panel.setFrame(frame, display: true)
    }

    private func endResize() {
        guard resizeStart != nil else { return }
        resizeStart = nil
        layout.width = panel.frame.width
    }

    /// The screen containing the mouse pointer, i.e. where the user is working.
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

private enum KeyCode {
    static let tab: UInt16 = 48
    static let `return`: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
}
