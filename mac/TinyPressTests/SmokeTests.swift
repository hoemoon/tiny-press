import AppKit
import XCTest

@testable import TinyPress

final class SmokeTests: XCTestCase {
    func testAppDelegateClassExists() {
        XCTAssertNotNil(NSStringFromClass(AppDelegate.self))
    }
}

/// Regression tests for the launch-time wiring that produces the menu bar
/// icon. The app shipped a build where the icon never appeared because
/// `@main` on `NSApplicationDelegate` did not connect the delegate to
/// `NSApp`, and an empty `NSApp.mainMenu` left `NSStatusBar.system.statusItem`
/// in a floating `NSSceneStatusItem` mode that is never attached to the
/// system menu bar. These tests guard against re-introducing either failure.
final class LaunchWiringRegressionTests: XCTestCase {
    private static let projectRoot: URL = {
        // SmokeTests.swift lives at TinyPressTests/SmokeTests.swift; project
        // root is two levels up.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testMainSwiftWiresDelegateAndMainMenu() throws {
        let main = try source("TinyPress/main.swift")
        XCTAssertTrue(
            main.contains("setActivationPolicy(.accessory)"),
            "main.swift must set .accessory or the app picks up a Dock icon."
        )
        XCTAssertTrue(
            main.contains("app.mainMenu"),
            """
            main.swift must assign NSApp.mainMenu before app.run(). Without
            it, macOS 26 returns a floating NSSceneStatusItem from
            NSStatusBar.system.statusItem(...) that never appears in the
            menu bar — the original "icon doesn't show" bug.
            """
        )
        XCTAssertTrue(
            main.contains("app.delegate = delegate"),
            "main.swift must connect AppDelegate to NSApp; otherwise " +
            "applicationDidFinishLaunching never fires."
        )
        XCTAssertTrue(
            main.contains("app.run()"),
            "main.swift must enter the run loop."
        )
    }

    func testAppDelegateDoesNotUseAtMain() throws {
        let delegate = try source("TinyPress/AppDelegate.swift")
        XCTAssertFalse(
            delegate.contains("@main"),
            """
            @main on a class conforming to NSApplicationDelegate (without a
            storyboard / nib) does not wire the delegate to NSApp in this
            project's configuration, so applicationDidFinishLaunching never
            runs. Keep the entry point in main.swift instead.
            """
        )
    }

    @MainActor
    func testStatusItemCreatesVisibleButtonWithImage() {
        // Replicates the launch path's mainMenu setup so the test is
        // immune to whatever NSApp the test harness starts with.
        let priorMenu = NSApp.mainMenu
        let menu = NSMenu()
        menu.addItem(NSMenuItem())
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = priorMenu }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        defer { NSStatusBar.system.removeStatusItem(item) }

        XCTAssertTrue(item.isVisible)
        let button = try? XCTUnwrap(item.button)
        button?.image = NSImage(
            systemSymbolName: "doc.text",
            accessibilityDescription: "tiny press"
        )
        XCTAssertNotNil(
            button?.image,
            "SF Symbol 'doc.text' must resolve on the deployment target. " +
            "If this fails on a future macOS, swap to a different symbol."
        )
    }
}
