import AppKit

/// Edge and corner resize handles for the borderless chat panel.
///
/// The window is transparent around the panel background, and macOS passes clicks on fully transparent
/// pixels through to the app behind, so native edge resizing doesn't work. This view sits
/// above the SwiftUI content, claims only thin bands straddling the panel edges (painted with
/// a nearly invisible fill so the window server delivers the clicks here), and forwards
/// drags to its owner. Everywhere else, `hitTest` returns `nil` so events reach SwiftUI.
final class PanelResizeOverlay: NSView {
    typealias Position = NSCursor.FrameResizePosition

    var onBegin: ((Position) -> Void)?
    var onDrag: (() -> Void)?
    var onEnd: (() -> Void)?

    /// Whether the hit zones are painted where they extend outside the panel. Turned off while the window
    /// server's Gaussian blur is on, since it would blur those bands too; edges can then be grabbed from inside only.
    var paintsOutsidePanel = true {
        didSet { if paintsOutsidePanel != oldValue { needsDisplay = true } }
    }

    /// Distance from the window edge to the panel edge.
    private let inset: CGFloat
    private let cornerRadius: CGFloat
    /// How far each band extends outside and inside the panel edge, and how far corner zones reach inward.
    private let outside: CGFloat = 6
    private let inside: CGFloat = 3
    private let cornerReach: CGFloat = 14

    private var hoveredPosition: Position?
    private var activePosition: Position?

    init(inset: CGFloat, cornerRadius: CGFloat) {
        self.inset = inset
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        position(at: convert(point, from: superview)) == nil ? nil : self
    }

    override func draw(_ dirtyRect: NSRect) {
        // Alpha must be non-zero for the window server to route clicks to this window.
        NSColor.black.withAlphaComponent(0.02).setFill()
        if !paintsOutsidePanel {
            let panel = bounds.insetBy(dx: inset, dy: inset)
            NSBezierPath(roundedRect: panel, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
        }
        for (_, rect) in zones() { rect.fill() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.activeAlways`: the panel is non-activating, so Spark usually isn't the active app.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        updateHover(position(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let position = position(at: convert(event.locationInWindow, from: nil)) else { return }
        activePosition = position
        Self.cursor(for: position).set()
        onBegin?(position)
    }

    override func mouseDragged(with event: NSEvent) {
        guard activePosition != nil else { return }
        onDrag?()
    }

    override func mouseUp(with event: NSEvent) {
        guard activePosition != nil else { return }
        activePosition = nil
        onEnd?()
        updateHover(position(at: convert(event.locationInWindow, from: nil)), force: true)
    }

    private func updateHover(_ position: Position?, force: Bool = false) {
        guard activePosition == nil, force || position != hoveredPosition else { return }
        hoveredPosition = position
        if let position {
            Self.cursor(for: position).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Geometry

    private func position(at point: NSPoint) -> Position? {
        zones().first { $0.rect.contains(point) }?.position
    }

    /// Hit zones in this view's (unflipped) coordinates. Corners come first so they win over edges.
    private func zones() -> [(position: Position, rect: NSRect)] {
        let glass = bounds.insetBy(dx: inset, dy: inset)
        guard glass.width > 2 * cornerReach, glass.height > 2 * cornerReach else { return [] }
        let band = outside + inside
        let corner = cornerReach + outside

        return [
            (.bottomLeft, NSRect(x: glass.minX - outside, y: glass.minY - outside, width: corner, height: corner)),
            (.bottomRight, NSRect(x: glass.maxX - cornerReach, y: glass.minY - outside, width: corner, height: corner)),
            (.topLeft, NSRect(x: glass.minX - outside, y: glass.maxY - cornerReach, width: corner, height: corner)),
            (.topRight, NSRect(x: glass.maxX - cornerReach, y: glass.maxY - cornerReach, width: corner, height: corner)),
            (.bottom, NSRect(x: glass.minX + cornerReach, y: glass.minY - outside, width: glass.width - 2 * cornerReach, height: band)),
            (.top, NSRect(x: glass.minX + cornerReach, y: glass.maxY - inside, width: glass.width - 2 * cornerReach, height: band)),
            (.left, NSRect(x: glass.minX - outside, y: glass.minY + cornerReach, width: band, height: glass.height - 2 * cornerReach)),
            (.right, NSRect(x: glass.maxX - inside, y: glass.minY + cornerReach, width: band, height: glass.height - 2 * cornerReach)),
        ]
    }

    private static func cursor(for position: Position) -> NSCursor {
        .frameResize(position: position, directions: .all)
    }
}

extension NSCursor.FrameResizePosition {
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
}
