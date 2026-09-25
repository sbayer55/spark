import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var braveKey: BraveSearchKey
    @AppStorage(Ollama.baseURLKey) private var ollamaURL = Ollama.defaultBaseURL
    @AppStorage(ChatRetention.key) private var retentionMinutes = ChatRetention.defaultMinutes
    @AppStorage(PanelAppearance.transparencyKey) private var transparency = PanelAppearance.defaultTransparency
    @AppStorage(PanelAppearance.blurKey) private var blur = PanelAppearance.defaultBlur

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
            Section("Appearance") {
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
            }
            Section("Ollama") {
                TextField("Server URL", text: $ollamaURL, prompt: Text(Ollama.defaultBaseURL))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }
            Section {
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
        .writingToolsBehavior(.disabled)
        .frame(width: 420)
        .fixedSize()
    }
}
