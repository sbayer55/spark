import AppKit
import SwiftUI

/// User-adjustable look of the chat panel's flat background, persisted in `UserDefaults`.
///
/// The panel is a flat rounded rect: an optional behind-window blur under a fill of the theme's background,
/// or the window background without a theme. Transparency fades that fill out. The blur comes from one of
/// two engines: `NSVisualEffectView` (Liquid Glass always draws a lit rim, which a flat panel can't have),
/// turned on or off by `Blur`, or the window server's Gaussian blur via private SkyLight calls, with an
/// adjustable radius (applied to the window by `PanelController`).
enum PanelAppearance {
    enum BlurEngine: String, CaseIterable, Identifiable {
        /// `NSVisualEffectView`.
        case standard
        /// The window server's Gaussian background blur (private SkyLight API, as in iTerm2).
        case gaussian

        var id: Self { self }

        var label: String {
            switch self {
            case .standard: "Standard"
            case .gaussian: "Gaussian"
            }
        }
    }

    enum Blur: String, CaseIterable, Identifiable {
        /// Raw value kept from the Liquid Glass variant it replaces, so stored settings carry over.
        case frosted
        case none = "clear"

        var id: Self { self }

        var label: String {
            switch self {
            case .frosted: "Frosted"
            case .none: "None"
            }
        }
    }

    static let transparencyKey = "panelTransparency"
    /// 1 is as see-through as the panel gets; 0 is fully solid.
    static let defaultTransparency = 1.0

    static let blurKey = "panelBlur"
    static let defaultBlur = Blur.frosted

    static let blurEngineKey = "panelBlurEngine"
    static let defaultBlurEngine = BlurEngine.standard

    /// The Gaussian engine's radius in points, within `SkyLight.radiusRange`.
    static let blurRadiusKey = "panelBlurRadius"
    static let defaultBlurRadius = 2.0

    /// The Gaussian blur radius to apply to the panel window from the stored settings; 0 when that engine is off.
    static func gaussianRadius(defaults: UserDefaults = .standard) -> Int {
        let engine = defaults.string(forKey: blurEngineKey).flatMap(BlurEngine.init) ?? defaultBlurEngine
        guard engine == .gaussian else { return 0 }
        // `double(forKey:)` also parses strings, as launch arguments (`-panelBlurRadius 20`) arrive.
        let radius = defaults.object(forKey: blurRadiusKey) == nil ? defaultBlurRadius : defaults.double(forKey: blurRadiusKey)
        return Int(radius.rounded())
    }

    /// Opacity of the fill over the blur. Themes keep enough fill to show their color, and without blur
    /// the panel keeps a faint fill so it doesn't disappear entirely. The Gaussian blur only covers
    /// non-transparent pixels, so that engine always keeps a barely visible fill for it to blur behind.
    static func fillOpacity(transparency: Double, blur: Blur, engine: BlurEngine, radius: Double,
                            themed: Bool) -> Double {
        let isBlurred = switch engine {
        case .standard: blur == .frosted
        case .gaussian: radius.rounded() > 0
        }
        let floor = if themed { 0.7 } else if !isBlurred { 0.15 } else if engine == .gaussian { 0.01 } else { 0.0 }
        return max(1 - transparency, floor)
    }
}

extension View {
    /// Puts the view on the panel's flat background in a rounded rect, styled by the user's
    /// `PanelAppearance` settings and the environment's theme.
    func panelBackground(cornerRadius: CGFloat) -> some View {
        modifier(PanelBackground(cornerRadius: cornerRadius))
    }
}

private struct PanelBackground: ViewModifier {
    @AppStorage(PanelAppearance.transparencyKey) private var transparency = PanelAppearance.defaultTransparency
    @AppStorage(PanelAppearance.blurKey) private var blur = PanelAppearance.defaultBlur
    @AppStorage(PanelAppearance.blurEngineKey) private var engine = PanelAppearance.defaultBlurEngine
    @AppStorage(PanelAppearance.blurRadiusKey) private var radius = PanelAppearance.defaultBlurRadius
    @Environment(\.theme) private var theme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        // Circular corners, to line up with the blur's mask.
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let fill = theme?.background ?? Color(nsColor: .windowBackgroundColor)
        let opacity = PanelAppearance.fillOpacity(transparency: transparency, blur: blur, engine: engine,
                                                  radius: radius, themed: theme != nil)
        content
            .background(fill.opacity(opacity), in: shape)
            .background {
                if engine == .standard && blur == .frosted {
                    BehindWindowBlur(cornerRadius: cornerRadius)
                }
            }
    }
}

/// Blurs whatever is behind the window, clipped to a rounded rect. Clipped with a mask image because
/// SwiftUI clipping doesn't apply to behind-window blending, which the window server composites.
private struct BehindWindowBlur: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
    }

    /// A stretchable rounded-rect mask: only the corners keep their size as the view resizes.
    private static func mask(cornerRadius radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
