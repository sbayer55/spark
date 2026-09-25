import CoreGraphics
import Foundation
import Observation

/// The panel's user-chosen size, persisted across launches.
///
/// The panel always fits its content: just the composer for an empty chat, growing as messages arrive.
/// A vertical resize sets how tall it may grow (`maxHeight`); until then, the message list is capped at
/// `PanelMetrics.maxListHeight`.
@MainActor
@Observable
final class PanelLayout {
    var width: CGFloat {
        didSet { defaults.set(Double(width), forKey: Self.widthKey) }
    }

    /// The tallest the user lets the panel grow (window height, including the inset), or `nil` for the default cap.
    var maxHeight: CGFloat? {
        didSet { defaults.set(maxHeight.map(Double.init), forKey: Self.heightKey) }
    }

    var isCustomized: Bool { maxHeight != nil || width != PanelMetrics.width }

    @ObservationIgnored private let defaults: UserDefaults
    private static let widthKey = "panelWidth"
    private static let heightKey = "panelHeight"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        width = (defaults.object(forKey: Self.widthKey) as? Double).map { CGFloat($0) } ?? PanelMetrics.width
        maxHeight = (defaults.object(forKey: Self.heightKey) as? Double).map { CGFloat($0) }
    }

    /// Returns to the default width and height cap.
    func reset() {
        width = PanelMetrics.width
        maxHeight = nil
    }
}
