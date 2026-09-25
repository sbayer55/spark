import KeyboardShortcuts
import SwiftUI

/// The Settings window: categories in a sidebar, the selected category's settings on the right.
struct SettingsView: View {
    let store: ChatStore
    @AppStorage(Theme.key) private var themeID = Theme.systemID
    @State private var category = SettingsCategory.general

    var body: some View {
        let theme = Theme.named(themeID)
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $category) { category in
                Label(category.title, systemImage: category.systemImage)
                    .tag(category)
            }
            .scrollContentBackground(theme == nil ? .automatic : .hidden)
            .background(theme?.surface ?? .clear)
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(category.title)
        }
        .frame(width: 780, height: 580)
        .environment(\.theme, theme)
        .themeStyle(theme)
        .preferredColorScheme(theme.map { $0.isDark ? .dark : .light })
        .containerBackground(theme.map { AnyShapeStyle($0.background) } ?? AnyShapeStyle(.windowBackground), for: .window)
        .writingToolsBehavior(.disabled)
    }

    @ViewBuilder
    private var detail: some View {
        switch category {
        case .general:
            GeneralSettingsView()
        case .models:
            ModelsSettingsView(store: store)
        case .research:
            ResearchSettingsView(store: store)
        case .appearance:
            VStack(spacing: 0) {
                PanelBackgroundSettingsView()
                Divider()
                ThemePicker()
            }
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, models, research, appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .research: "Research"
        case .appearance: "Appearance"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .models: "cpu"
        case .research: "globe"
        case .appearance: "paintpalette"
        }
    }
}

/// A grouped form that lets the theme's window background show through.
private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(theme == nil ? .automatic : .hidden)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(ChatRetention.key) private var retentionMinutes = ChatRetention.defaultMinutes
    @AppStorage(SystemPrompt.key) private var systemPrompt = ""

    var body: some View {
        SettingsForm {
            Section {
                KeyboardShortcuts.Recorder("Toggle Spark:", name: .togglePanel)
            }
            Section {
                Picker("Keep chat after closing:", selection: $retentionMinutes) {
                    ForEach(ChatRetention.options, id: \.minutes) { option in
                        Text(option.label).tag(option.minutes)
                    }
                }
            } footer: {
                Text("When you reopen Spark after this long, it starts a new chat.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if systemPrompt.isEmpty {
                            Text("e.g. Answer concisely. Use metric units.")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("System prompt")
            } header: {
                Text("System prompt")
            } footer: {
                Text("Sent to the model at the start of every chat, with any provider. In TL;DR mode a brevity instruction is added after it; in Research mode it shapes the final answer. Leave empty for none.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ModelsSettingsView: View {
    let store: ChatStore
    @AppStorage(Ollama.baseURLKey) private var ollamaURL = Ollama.defaultBaseURL

    var body: some View {
        SettingsForm {
            Section("Ollama") {
                TextField("Server URL", text: $ollamaURL, prompt: Text(Ollama.defaultBaseURL))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }
            AnthropicSection(store: store)
            BedrockSection(store: store)
            CustomProvidersSection(store: store)
        }
    }
}

private struct ResearchSettingsView: View {
    let store: ChatStore

    var body: some View {
        SettingsForm {
            Section {
                @Bindable var braveKey = store.braveKey
                SecureField("Brave Search API key", text: $braveKey.key)
                    .textContentType(.password)
                    .autocorrectionDisabled()
            } footer: {
                Text("Enables the Research button in the composer. Get a key at brave.com/search/api. Stored in your Keychain.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The panel's transparency and background blur, above the theme grid in Appearance.
private struct PanelBackgroundSettingsView: View {
    @AppStorage(PanelAppearance.transparencyKey) private var transparency = PanelAppearance.defaultTransparency
    @AppStorage(PanelAppearance.blurKey) private var blur = PanelAppearance.defaultBlur
    @AppStorage(PanelAppearance.blurEngineKey) private var engine = PanelAppearance.defaultBlurEngine
    @AppStorage(PanelAppearance.blurRadiusKey) private var radius = PanelAppearance.defaultBlurRadius

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Transparency:")
                    .gridColumnAlignment(.trailing)
                Slider(value: $transparency, in: 0...1) {
                    Text("Transparency")
                } minimumValueLabel: {
                    Text("Solid")
                } maximumValueLabel: {
                    Text("Clear")
                }
                .labelsHidden()
            }
            GridRow {
                Text("Blur engine:")
                Picker("Blur engine", selection: $engine) {
                    ForEach(PanelAppearance.BlurEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                switch engine {
                case .standard:
                    Text("Background blur:")
                    Picker("Background blur", selection: $blur) {
                        ForEach(PanelAppearance.Blur.allCases) { blur in
                            Text(blur.label).tag(blur)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                case .gaussian:
                    Text("Blur radius:")
                    HStack {
                        Slider(value: $radius, in: SkyLight.radiusRange, step: 1) {
                            Text("Blur radius")
                        }
                        .labelsHidden()
                        Text("\(Int(radius.rounded())) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var footnote: String {
        switch engine {
        case .standard:
            "The system's frosted material."
        case .gaussian where !SkyLight.isAvailable:
            "This version of macOS doesn't offer the window server blur, so the panel isn't blurred."
        case .gaussian:
            "The window server's Gaussian blur, through a private macOS API (as iTerm2 uses). A future macOS may remove it."
        }
    }
}
