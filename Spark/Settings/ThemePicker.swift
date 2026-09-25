import SwiftUI

/// The Appearance settings category: a grid of theme cards, each previewing the chat panel in that theme's colors.
struct ThemePicker: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", light = "Light", dark = "Dark"
        var id: Self { self }

        func includes(_ theme: Theme) -> Bool {
            switch self {
            case .all: true
            case .light: !theme.isDark
            case .dark: theme.isDark
            }
        }
    }

    @AppStorage(Theme.key) private var themeID = Theme.systemID
    @State private var filter = Filter.all

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Theme")
                    .font(.headline)
                Text(Theme.named(themeID)?.name ?? "System")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        Section {
                            card(for: nil)
                        } header: {
                            header("Default")
                        }
                        ForEach(Theme.Category.allCases) { category in
                            let themes = Theme.all.filter { $0.category == category && filter.includes($0) }
                            if !themes.isEmpty {
                                Section {
                                    ForEach(themes) { card(for: $0) }
                                } header: {
                                    header(category.rawValue)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .onAppear { proxy.scrollTo(themeID, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    private func card(for theme: Theme?) -> some View {
        let id = theme?.id ?? Theme.systemID
        return ThemeCard(theme: theme, isSelected: themeID == id) {
            themeID = id
        }
        .id(id)
    }
}

private struct ThemeCard: View {
    let theme: Theme?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ThemePreview(theme: theme)
                    .frame(height: 100)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    }
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3)
                    }
                HStack(spacing: 4) {
                    Text(theme?.name ?? "System")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme?.name ?? "System")
        .accessibilityValue(theme.map { $0.isDark ? "Dark" : "Light" } ?? "Follows system appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature chat panel: a user bubble, an assistant reply with a link-colored word and a code block,
/// and a strip of the palette's hues.
private struct ThemePreview: View {
    let theme: Theme?

    var body: some View {
        ZStack {
            if let theme {
                theme.background
                content(for: theme)
            } else {
                systemBackdrop
            }
        }
    }

    private func content(for theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Spacer()
                bar(theme.foreground, width: 44)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(theme.accent.opacity(0.22), in: .rect(cornerRadius: 6, style: .continuous))
            }
            HStack(spacing: 3) {
                bar(theme.foreground, width: 30)
                bar(theme.accent, width: 22)
                bar(theme.foreground, width: 34)
            }
            bar(theme.muted, width: 58)
            VStack(alignment: .leading, spacing: 3) {
                bar(theme.foreground.opacity(0.85), width: 50)
                bar(theme.foreground.opacity(0.85), width: 36)
            }
            .padding(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 4, style: .continuous))
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(Array(theme.swatches.enumerated()), id: \.offset) { _, color in
                    color
                }
            }
            .frame(height: 8)
            .clipShape(.capsule)
        }
        .padding(9)
    }

    /// The default look: the flat frosted panel over a colorful backdrop, with system colors.
    private var systemBackdrop: some View {
        LinearGradient(colors: [.blue, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Spacer()
                        bar(.primary, width: 44)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.25), in: .rect(cornerRadius: 6, style: .continuous))
                    }
                    bar(.primary, width: 80)
                    bar(.secondary, width: 58)
                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                .padding(8)
            }
    }

    private func bar(_ style: some ShapeStyle, width: CGFloat) -> some View {
        Capsule()
            .fill(style)
            .frame(width: width, height: 5)
    }
}
