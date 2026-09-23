import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.panelController.toggle()
        }
    }
}
