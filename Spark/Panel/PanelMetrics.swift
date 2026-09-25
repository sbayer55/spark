import CoreGraphics

enum PanelMetrics {
    /// Default panel width, including the transparent inset around the panel background.
    static let width: CGFloat = 680
    /// Smallest size the user can resize the panel to.
    static let minSize = CGSize(width: 420, height: 120)
    /// Transparent margin so the panel's edges aren't clipped by the window.
    static let inset: CGFloat = 12
    /// Corner radius of the chat panel's background.
    static let cornerRadius: CGFloat = 22
    /// While the panel sizes itself to its content, the message list scrolls once it exceeds this height.
    static let maxListHeight: CGFloat = 460
}
