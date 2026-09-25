import SwiftUI

/// User-adjustable text size for the chat panel (⌘= / ⌘- / ⌘0), persisted in `UserDefaults`.
///
/// macOS text styles don't scale with Dynamic Type, so chat text sets explicit point sizes
/// through `scaledFont(_:)`, multiplied by the `textScale` environment value.
enum TextSize {
    enum Command {
        case increase, decrease, reset
    }

    static let key = "textScale"
    static let defaultScale = 1.0
    static let steps: [Double] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5, 1.75, 2.0]
    /// Largest font for the composer's controls (model picker, Research toggle). Chat and composer text aren't capped.
    static let maxControlFontSize: CGFloat = 14
    /// The composer's controls use `.callout` (12 pt at 1×).
    private static let controlFontSize: CGFloat = 12

    /// `scale`, limited so that `.callout` text stays within `maxControlFontSize`; for sizing that tracks
    /// the controls' text, such as padding.
    static func controlScale(for scale: Double) -> Double {
        min(scale, maxControlFontSize / controlFontSize)
    }

    static func apply(_ command: Command, defaults: UserDefaults = .standard) {
        let current = defaults.object(forKey: key) as? Double ?? defaultScale
        let next: Double = switch command {
        case .increase: steps.first { $0 > current + 0.001 } ?? steps.last!
        case .decrease: steps.last { $0 < current - 0.001 } ?? steps.first!
        case .reset: defaultScale
        }
        defaults.set(next, forKey: key)
    }
}

extension EnvironmentValues {
    @Entry var textScale: Double = TextSize.defaultScale
}

extension View {
    /// Sets a system font at the macOS default size of `style`, multiplied by the environment's `textScale`
    /// and limited to `maxSize` points.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil,
                    maxSize: CGFloat = .infinity) -> some View {
        modifier(ScaledFont(size: style.defaultPointSize, weight: weight, design: design, maxSize: maxSize))
    }

    /// Sets a system font of `size` points, multiplied by the environment's `textScale` and limited to `maxSize` points.
    func scaledFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil,
                    maxSize: CGFloat = .infinity) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, maxSize: maxSize))
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    let maxSize: CGFloat

    func body(content: Content) -> some View {
        content.font(.system(size: min(size * scale, maxSize), weight: weight, design: design))
    }
}

private extension Font.TextStyle {
    /// macOS default point sizes for each text style.
    var defaultPointSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }
}
