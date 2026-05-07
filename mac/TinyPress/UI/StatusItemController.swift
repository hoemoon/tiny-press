import AppKit

/// Owns the `NSStatusItem` and the `NSPopover` it opens.
///
/// Keeps `AppDelegate` slim: the delegate just installs this controller
/// once at launch and forwards a callback for "Settings…" so it can
/// surface the preferences window from a single place.
@MainActor
final class StatusItemController: NSObject {
    typealias OpenSettingsHandler = @MainActor () -> Void

    private let appState: AppState
    private let openSettings: OpenSettingsHandler
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private lazy var popoverController = MenuBarPopoverViewController(
        appState: appState,
        openSettings: openSettings
    )
    private var addSiteController: AddSiteWindowController?

    init(
        appState: AppState,
        openSettings: @escaping OpenSettingsHandler
    ) {
        self.appState = appState
        self.openSettings = openSettings
        super.init()
    }

    /// Install the menu bar item. Idempotent.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "doc.text",
                accessibilityDescription: "tiny press"
            )
            button.toolTip = "tiny press"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        statusItem = item

        popover.contentViewController = popoverController
        popover.behavior = .transient
        popoverController.onAddSite = { [weak self] in self?.presentAddSite() }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func presentAddSite() {
        popover.performClose(nil)
        if addSiteController == nil {
            addSiteController = AddSiteWindowController(appState: appState)
        }
        addSiteController?.showWindow(nil)
        addSiteController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
