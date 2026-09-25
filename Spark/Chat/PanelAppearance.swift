import SwiftUI

/// User-adjustable look of the chat panel's Liquid Glass surfaces, persisted in `UserDefaults`.
///
/// Liquid Glass has no blur radius or opacity knobs, so the two settings map onto what it does offer:
/// blur picks the glass variant (`.regular` frosts what's behind the panel, `.clear` barely does), and
/// transparency fades in a solid window-background fill over the glass.
enum PanelAppearance {
    enum Blur: String, CaseIterable, Identifiable {
        case frosted, clear

        var id: Self { self }

        var label: String {
            switch self {
            case .frosted: "Frosted"
            case .clear: "Clear"
            }
        }

        var glass: Glass {
            switch self {
            case .frosted: .regular
            case .clear: .clear
            }
        }
    }

    static let transparencyKey = "panelTransparency"
    /// 1 is plain glass; 0 is fully solid.
    static let defaultTransparency = 1.0

    static let blurKey = "panelBlur"
    static let defaultBlur = Blur.frosted
}

extension View {
    /// Puts the view on Liquid Glass in a rounded rect, styled by the user's `PanelAppearance` settings.
    func panelGlass(cornerRadius: CGFloat) -> some View {
        modifier(PanelGlass(cornerRadius: cornerRadius))
    }
}

private struct PanelGlass: ViewModifier {
    @AppStorage(PanelAppearance.transparencyKey) private var transparency = PanelAppearance.defaultTransparency
    @AppStorage(PanelAppearance.blurKey) private var blur = PanelAppearance.defaultBlur
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color(nsColor: .windowBackgroundColor).opacity(1 - transparency), in: shape)
            .glassEffect(blur.glass, in: shape)
    }
}
