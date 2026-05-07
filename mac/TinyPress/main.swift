import AppKit

// `@main` synthesised on `NSApplicationDelegate` does not wire the delegate
// to `NSApp` in this configuration (no storyboard, no nib), so the app would
// boot into the run loop with no delegate and `applicationDidFinishLaunching`
// would never fire. Setting it explicitly here is the standard programmatic
// AppKit entry point.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Without a main menu, macOS 26 returns a floating `NSSceneStatusItem` from
// `NSStatusBar.system.statusItem(...)` that never attaches to the system
// menu bar — the icon is created but never rendered. Giving NSApp an empty
// (or near-empty) main menu is enough to put it back on the standard path.
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(
    withTitle: "Quit tiny press",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
)
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

let delegate = AppDelegate()
app.delegate = delegate
app.run()
