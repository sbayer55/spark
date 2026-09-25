import AppKit
import SwiftUI

/// Owns the chat panel and its chats, and handles show/hide/positioning/sizing.
@MainActor
final class PanelController {
    let store: ChatStore
    let layout: PanelLayout
    private let panel: ChatPanel
    private let resizeOverlay: PanelResizeOverlay

    /// When the panel was last hidden; `nil` while it's showing. Continuous clock, so time asleep counts.
    private var hiddenAt: ContinuousClock.Instant?

    /// The in-progress user resize: which edge or corner, and the frame and mouse location it started from.
    private var resizeStart: (position: NSCursor.FrameResizePosition, frame: NSRect, mouse: NSPoint)?
    /// The content's last reported height, to fit the panel to it again after a user resize.
    private var contentHeight: CGFloat?

    /// SwiftUI's action for opening the Settings scene, supplied by the hosted `ChatView`.
    private var openSettingsAction: OpenSettingsAction?

    init(store: ChatStore = ChatStore(), layout: PanelLayout = PanelLayout()) {
        self.store = store
        self.layout = layout
        panel = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: layout.width, height: 120))
        resizeOverlay = PanelResizeOverlay(inset: PanelMetrics.inset, cornerRadius: PanelMetrics.cornerRadius)

        let hostingView = NSHostingView(rootView: ChatView(
            store: store,
            layout: layout,
            onHeightChange: { [weak self] height in self?.resize(toContentHeight: height) },
            onOpenSettingsAction: { [weak self] action in self?.openSettingsAction = action }
        ))
        hostingView.sizingOptions = []

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
        applyGaussianBlur()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyThemeAppearance()
                self?.applyGaussianBlur()
            }
        }
    }

    /// Sets the window server's Gaussian background blur from the appearance settings (0 turns it off).
    /// While it's on, the resize overlay stops painting outside the panel so that margin isn't blurred too.
    private func applyGaussianBlur() {
        let radius = PanelAppearance.gaussianRadius()
        SkyLight.setBackgroundBlur(radius: radius, for: panel)
        resizeOverlay.paintsOutsidePanel = radius == 0
    }

    /// Matches the panel's appearance to the theme's light or dark background, so the blur, menus, and
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
            // Lay out now so an expired chat's replacement has already resized the panel (down to just the
            // composer) before it's positioned and shown, rather than opening at the old size and shrinking.
            panel.contentView?.layoutSubtreeIfNeeded()
            position(on: activeScreen())
        }
        hiddenAt = nil
        panel.makeKeyAndOrderFront(nil)
        applyGaussianBlur()
        store.requestFocus()
        // Cheap local call; picks up models pulled or servers started since last open.
        Task { await store.refreshModels() }
    }

    func hide() {
        store.cancelSwitcher()
        store.dismissShortcuts()
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

    /// Closes the panel and brings the Settings window to the front.
    func openSettings() {
        // Menu bar (LSUIElement) apps must activate first or the window opens behind other apps. The panel is
        // non-activating, so another app is still active here and it ignores the cooperative `NSApp.activate()`
        // (Settings opened behind it when tested). `ignoringOtherApps:` is marked "to be deprecated" but still works.
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction?()
        hide()
    }

    /// Opens the panel with the keyboard shortcuts overlay showing (⌘/ from elsewhere in the app, e.g. Settings).
    func showShortcuts() {
        store.showShortcuts()
        show()
    }

    private func handleEscape() {
        if store.isShowingShortcuts {
            store.dismissShortcuts()
        } else if !store.active.cancelStreaming() {
            hide()
        }
    }

    // MARK: - Chat keys

    /// ⌘N / ⌘W / ⌘, (Settings) / ⌘/ (shortcuts), ⇧Tab (next chat mode), and the ⌃Tab switcher: hold ⌃ and press Tab (⇧Tab backward) to move, release ⌃ to switch.
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
        if event.keyCode == KeyCode.tab, modifiers == .shift, !store.isSwitcherOpen {
            store.dismissShortcuts()
            store.active.cycleMode()
            return true
        }

        if modifiers == .command && event.charactersIgnoringModifiers == "/" {
            store.toggleShortcuts()
            return true
        }
        // Typing anything else closes the shortcuts list and carries on as usual (Escape closes it in `handleEscape`).
        if store.isShowingShortcuts && event.keyCode != KeyCode.escape {
            store.dismissShortcuts()
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
            case ",": openSettings(); return true
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
    /// The content caps its own height at `layout.maxHeight`.
    private func resize(toContentHeight height: CGFloat) {
        let height = height.rounded(.up)
        contentHeight = height
        // While the user drags an edge, the drag sets the frame; the content catches up once it ends.
        guard resizeStart == nil else { return }
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

    /// Applies the mouse's movement since `beginResize` to the dragged edges. A vertical drag sets the
    /// maximum height; once it ends, the panel shrinks back to its content if that's shorter.
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
            layout.maxHeight = frame.height
        }
        panel.setFrame(frame, display: true)
    }

    private func endResize() {
        guard resizeStart != nil else { return }
        resizeStart = nil
        layout.width = panel.frame.width
        if let contentHeight {
            resize(toContentHeight: contentHeight)
        }
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
