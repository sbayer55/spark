import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(Theme.key) private var themeID = Theme.systemID

    var body: some View {
        let theme = Theme.named(themeID)
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Appearance", systemImage: "paintpalette") {
                ThemePicker()
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
        }
        .formStyle(.grouped)
        // Let the theme's window background show through.
        .scrollContentBackground(theme == nil ? .automatic : .hidden)
        .frame(width: 420)
        .fixedSize()
    }
}
