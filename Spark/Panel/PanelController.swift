import AppKit
import SwiftUI

/// Owns the chat panel and its view model, and handles show/hide/positioning/sizing.
@MainActor
final class PanelController {
    let viewModel: ChatViewModel
    let layout: PanelLayout
    private let panel: ChatPanel

    /// The in-progress user resize: which edge or corner, and the frame and mouse location it started from.
    private var resizeStart: (position: NSCursor.FrameResizePosition, frame: NSRect, mouse: NSPoint)?

    init(viewModel: ChatViewModel = ChatViewModel(), layout: PanelLayout = PanelLayout()) {
        self.viewModel = viewModel
        self.layout = layout
        panel = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: layout.width, height: layout.fixedHeight ?? 120))

        let hostingView = NSHostingView(rootView: ChatView(model: viewModel, layout: layout) { [weak self] height in
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
            position(on: activeScreen())
        }
        panel.makeKeyAndOrderFront(nil)
        viewModel.requestFocus()
        // Cheap local call; picks up models pulled or servers started since last open.
        Task { await viewModel.refreshModels() }
    }

    func hide() {
        panel.orderOut(nil)
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
        if !viewModel.cancelStreaming() {
            hide()
        }
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
