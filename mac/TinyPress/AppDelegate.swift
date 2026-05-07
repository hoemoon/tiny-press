import AppKit
import TinyPressKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(appState: appState) { [weak self] in
            self?.openSettings()
        }
        controller.install()
        statusItemController = controller

        Task { await appState.refresh() }
        _ = TinyPressKit.version
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await appState.shutdown() }
    }

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: appState)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
