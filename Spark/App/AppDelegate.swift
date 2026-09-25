import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController = PanelController()
    private var availabilityTask: Task<Void, Never>?

    /// How often provider availability is re-checked for the menu bar icon.
    private static let availabilityInterval: Duration = .seconds(60)

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.panelController.toggle()
        }
        startAvailabilityChecks()
        if LaunchOptions.showPanelOnLaunch {
            panelController.show()
        }

        // Networks and local servers often change across sleep; re-check right away on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startAvailabilityChecks() }
        }
    }

    /// (Re)starts the periodic provider check, running one immediately.
    private func startAvailabilityChecks() {
        availabilityTask?.cancel()
        availabilityTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.panelController.store.refreshModels()
                try? await Task.sleep(for: Self.availabilityInterval)
            }
        }
    }
}
