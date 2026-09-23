import CoreGraphics
import Foundation
import Observation

/// The panel's user-chosen size, persisted across launches.
///
/// Until the user resizes the panel vertically, `fixedHeight` is `nil` and the panel grows
/// with its content. After a vertical resize, the height stays where the user left it.
@MainActor
@Observable
final class PanelLayout {
    var width: CGFloat {
        didSet { defaults.set(Double(width), forKey: Self.widthKey) }
    }

    /// The user's chosen height, or `nil` while the panel sizes itself to its content.
    var fixedHeight: CGFloat? {
        didSet { defaults.set(fixedHeight.map(Double.init), forKey: Self.heightKey) }
    }

    var isHeightFixed: Bool { fixedHeight != nil }
    var isCustomized: Bool { isHeightFixed || width != PanelMetrics.width }

    @ObservationIgnored private let defaults: UserDefaults
    private static let widthKey = "panelWidth"
    private static let heightKey = "panelHeight"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        width = (defaults.object(forKey: Self.widthKey) as? Double).map { CGFloat($0) } ?? PanelMetrics.width
        fixedHeight = (defaults.object(forKey: Self.heightKey) as? Double).map { CGFloat($0) }
    }

    /// Returns to the default width and content-driven height.
    func reset() {
        width = PanelMetrics.width
        fixedHeight = nil
    }
}
