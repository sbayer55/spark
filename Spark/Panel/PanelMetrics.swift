import CoreGraphics

enum PanelMetrics {
    /// Total panel width, including the transparent inset around the glass.
    static let width: CGFloat = 680
    /// Transparent margin so glass edges and shadows aren't clipped by the window.
    static let inset: CGFloat = 12
    /// The message list scrolls once its content exceeds this height.
    static let maxListHeight: CGFloat = 460
}
