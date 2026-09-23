import SwiftUI

@main
struct SparkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Spark", systemImage: "sparkle") {
            SparkMenu(panelController: appDelegate.panelController)
        }

        Settings {
            SettingsView()
        }
    }
}

private struct SparkMenu: View {
    let panelController: PanelController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("New Chat") {
            panelController.viewModel.newChat()
            panelController.show()
        }
        .keyboardShortcut("n")

        Button("Settings…") {
            // Menu bar (LSUIElement) apps must activate first or the window opens behind other apps.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Spark") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
