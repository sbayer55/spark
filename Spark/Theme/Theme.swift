import SwiftUI

/// A color theme for the chat panel, persisted in `UserDefaults` by `id`.
/// No theme (`Theme.systemID`) keeps the default frosted look that follows the system appearance.
struct Theme: Identifiable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case warm = "Warm & Retro"
        case pastel = "Pastel & Modern"
        case cool = "Cool & Nordic"
        case classic = "Classic & Precision"
        case editor = "Editor Favorites"
        case minimal = "Minimal & Monochrome"

        var id: Self { self }
    }

    let id: String
    let name: String
    let category: Category
    let isDark: Bool

    /// The panel's fill.
    let background: Color
    /// Code blocks and other raised content.
    let surface: Color
    let foreground: Color
    /// Secondary text: captions, list markers, placeholders.
    let muted: Color
    /// Links, the user's message bubble, and selection highlights.
    let accent: Color
    let red: Color
    let orange: Color
    let yellow: Color
    let green: Color
    let cyan: Color
    let blue: Color
    let purple: Color

    /// The palette's hues, for previews.
    var swatches: [Color] { [red, orange, yellow, green, cyan, blue, purple] }

    init(
        _ id: String, _ name: String, _ category: Category, dark isDark: Bool,
        bg: UInt32, surface: UInt32, fg: UInt32, muted: UInt32, accent: UInt32,
        red: UInt32, orange: UInt32, yellow: UInt32, green: UInt32, cyan: UInt32, blue: UInt32, purple: UInt32
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.isDark = isDark
        background = Color(hex: bg)
        self.surface = Color(hex: surface)
        foreground = Color(hex: fg)
        self.muted = Color(hex: muted)
        self.accent = Color(hex: accent)
        self.red = Color(hex: red)
        self.orange = Color(hex: orange)
        self.yellow = Color(hex: yellow)
        self.green = Color(hex: green)
        self.cyan = Color(hex: cyan)
        self.blue = Color(hex: blue)
        self.purple = Color(hex: purple)
    }

    // MARK: - Selection

    static let key = "themeID"
    static let systemID = "system"

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The theme with `id`, or `nil` for the system look (including unknown IDs).
    static func named(_ id: String) -> Theme? {
        byID[id]
    }

    static func current(defaults: UserDefaults = .standard) -> Theme? {
        defaults.string(forKey: key).flatMap(named)
    }
}

extension Color {
    /// A color from a 24-bit `0xRRGGBB` sRGB value.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension EnvironmentValues {
    /// The chat panel's theme; `nil` for the system look.
    @Entry var theme: Theme? = nil
}

extension View {
    /// Applies the theme's text colors (primary, secondary, tertiary) and accent, or the system styles without one.
    /// Doesn't branch on the theme, so switching themes keeps view identity (focus, scroll position).
    func themeStyle(_ theme: Theme?) -> some View {
        foregroundStyle(
            theme.map { AnyShapeStyle($0.foreground) } ?? AnyShapeStyle(.primary),
            theme.map { AnyShapeStyle($0.muted) } ?? AnyShapeStyle(.secondary),
            theme.map { AnyShapeStyle($0.muted.opacity(0.7)) } ?? AnyShapeStyle(.tertiary)
        )
        .tint(theme?.accent)
    }
}
