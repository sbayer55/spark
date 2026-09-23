import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(Ollama.baseURLKey) private var ollamaURL = Ollama.defaultBaseURL
    @AppStorage(ChatRetention.key) private var retentionMinutes = ChatRetention.defaultMinutes

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
        .writingToolsBehavior(.disabled)
        .frame(width: 420)
        .fixedSize()
    }
}
