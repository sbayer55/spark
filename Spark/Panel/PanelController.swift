import AppKit
import SwiftUI

/// Owns the chat panel and its view model, and handles show/hide/positioning.
@MainActor
final class PanelController {
    let viewModel: ChatViewModel
    private let panel: ChatPanel

    init(viewModel: ChatViewModel = ChatViewModel()) {
        self.viewModel = viewModel
        panel = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: 120))

        let hostingView = NSHostingView(rootView: ChatView(model: viewModel) { [weak self] height in
            self?.resize(toContentHeight: height)
        })
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        panel.onEscape = { [weak self] in self?.handleEscape() }
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

    private func handleEscape() {
        if !viewModel.cancelStreaming() {
            hide()
        }
    }

    // MARK: - Layout

    /// Centers the panel horizontally with its top edge in the upper third of the screen.
    private func position(on screen: NSScreen?) {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = panel.frame.size
        let top = visible.maxY - visible.height / 6
        panel.setFrameTopLeftPoint(NSPoint(x: visible.midX - size.width / 2, y: top))
    }

    /// Grows or shrinks the panel to fit its content, keeping the top edge fixed.
    private func resize(toContentHeight height: CGFloat) {
        let height = height.rounded(.up)
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    /// The screen containing the mouse pointer, i.e. where the user is working.
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
