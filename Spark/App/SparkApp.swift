import SwiftUI

@main
struct SparkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SparkMenu(panelController: appDelegate.panelController)
        } label: {
            StatusItemLabel(registry: appDelegate.panelController.store.registry)
        }

        Settings {
            SettingsView()
        }
    }
}

/// The menu bar icon; badged while any provider is unavailable.
private struct StatusItemLabel: View {
    let registry: ProviderRegistry

    var body: some View {
        Image(nsImage: registry.unavailableProviders.isEmpty ? StatusIcon.normal : StatusIcon.degraded)
    }
}

private struct SparkMenu: View {
    let panelController: PanelController
    @Environment(\.openSettings) private var openSettings

    private var registry: ProviderRegistry { panelController.store.registry }

    var body: some View {
        if !registry.unavailableProviders.isEmpty {
            Section("Unavailable") {
                ForEach(registry.unavailableProviders, id: \.id) { provider in
                    Label(registry.errors[provider.id] ?? "\(provider.displayName) is unavailable",
                          systemImage: "exclamationmark.triangle")
                }
                Button("Check Again") {
                    Task { await panelController.store.refreshModels() }
                }
            }
            Divider()
        }

        Button("New Chat") {
            panelController.store.newChat()
            panelController.show()
        }
        .keyboardShortcut("n")

        Button("Reset Panel Size") {
            panelController.resetSize()
        }
        .disabled(!panelController.layout.isCustomized)

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
