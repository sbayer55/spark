import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let store: ChatStore
    @AppStorage(Theme.key) private var themeID = Theme.systemID

    var body: some View {
        let theme = Theme.named(themeID)
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(store: store)
            }
            Tab("Appearance", systemImage: "paintpalette") {
                VStack(spacing: 0) {
                    GlassSettingsView()
                    Divider()
                    ThemePicker()
                }
            }
        }
        .environment(\.theme, theme)
        .themeStyle(theme)
        .preferredColorScheme(theme.map { $0.isDark ? .dark : .light })
        .containerBackground(theme.map { AnyShapeStyle($0.background) } ?? AnyShapeStyle(.windowBackground), for: .window)
        .writingToolsBehavior(.disabled)
    }
}

private struct GeneralSettingsView: View {
    let store: ChatStore
    @AppStorage(Ollama.baseURLKey) private var ollamaURL = Ollama.defaultBaseURL
    @AppStorage(ChatRetention.key) private var retentionMinutes = ChatRetention.defaultMinutes
    @Environment(\.theme) private var theme

    var body: some View {
        Form {
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
            Section("Ollama") {
                TextField("Server URL", text: $ollamaURL, prompt: Text(Ollama.defaultBaseURL))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }
            CustomProvidersSection(store: store)
            Section {
                @Bindable var braveKey = store.braveKey
                SecureField("Brave Search API key", text: $braveKey.key)
                    .textContentType(.password)
                    .autocorrectionDisabled()
            } header: {
                Text("Research")
            } footer: {
                Text("Enables the Research button in the composer. Get a key at brave.com/search/api. Stored in your Keychain.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Let the theme's window background show through.
        .scrollContentBackground(theme == nil ? .automatic : .hidden)
        .frame(width: 420)
        .fixedSize()
    }
}

/// The panel's glass transparency and background blur, above the theme grid on the Appearance tab.
private struct GlassSettingsView: View {
    @AppStorage(PanelAppearance.transparencyKey) private var transparency = PanelAppearance.defaultTransparency
    @AppStorage(PanelAppearance.blurKey) private var blur = PanelAppearance.defaultBlur

    var body: some View {
        HStack(spacing: 24) {
            Slider(value: $transparency, in: 0...1) {
                Text("Transparency:")
            } minimumValueLabel: {
                Text("Solid")
            } maximumValueLabel: {
                Text("Glass")
            }
            Picker("Background blur:", selection: $blur) {
                ForEach(PanelAppearance.Blur.allCases) { blur in
                    Text(blur.label).tag(blur)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
