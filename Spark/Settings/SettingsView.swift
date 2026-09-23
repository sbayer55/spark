import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(Ollama.baseURLKey) private var ollamaURL = Ollama.defaultBaseURL

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Spark:", name: .togglePanel)
            }
            Section("Ollama") {
                TextField("Server URL", text: $ollamaURL, prompt: Text(Ollama.defaultBaseURL))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
