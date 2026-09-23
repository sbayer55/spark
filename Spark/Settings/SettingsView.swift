import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle Spark:", name: .togglePanel)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
