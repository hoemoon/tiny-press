import AppKit

/// Three-tab preferences window. Programmatic AppKit, single instance.
@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private enum Tab: String, CaseIterable {
        case general, sites, advanced

        var title: String {
            switch self {
            case .general: return "General"
            case .sites: return "Sites"
            case .advanced: return "Advanced"
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "gearshape"
            case .sites: return "list.bullet"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    private let appState: AppState
    private var tabControllers: [Tab: NSViewController] = [:]
    private var currentTab: Tab = .general

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "tiny press"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        installToolbar()
        select(.general)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func installToolbar() {
        let toolbar = NSToolbar(identifier: "TinyPressSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(Tab.general.rawValue)
        window?.toolbar = toolbar
    }

    private func select(_ tab: Tab) {
        currentTab = tab
        let controller =
            tabControllers[tab]
            ?? makeController(for: tab)
        tabControllers[tab] = controller
        window?.contentViewController = controller
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
    }

    private func makeController(for tab: Tab) -> NSViewController {
        switch tab {
        case .general: return GeneralPaneViewController(appState: appState)
        case .sites: return SitesPaneViewController(appState: appState)
        case .advanced: return AdvancedPaneViewController(appState: appState)
        }
    }

    // MARK: NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = Tab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.image = NSImage(
            systemSymbolName: tab.symbolName,
            accessibilityDescription: tab.title
        )
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(tab)
    }
}
