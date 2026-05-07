import XCTest

@testable import TinyPress

final class BuildCoordinatorTests: XCTestCase {
    private var sourceDir: URL!

    override func setUpWithError() throws {
        sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-coordinator-\(UUID().uuidString)", isDirectory: true)
        let posts = sourceDir.appendingPathComponent("content/posts", isDirectory: true)
        try FileManager.default.createDirectory(at: posts, withIntermediateDirectories: true)
        try """
            title: Coordinator
            theme: default
            language: en
            permalinkStyle: pretty
            """.write(
                to: sourceDir.appendingPathComponent("tinypress.yml"),
                atomically: true,
                encoding: .utf8
            )
        try """
            ---
            title: First
            date: 2026-01-01
            ---

            Hello.
            """.write(
                to: posts.appendingPathComponent("first.md"),
                atomically: true,
                encoding: .utf8
            )
    }

    override func tearDownWithError() throws {
        if let sourceDir { try? FileManager.default.removeItem(at: sourceDir) }
    }

    @MainActor
    func testFullCycleBuildsAndServesAndReloadsOnFileChange() async throws {
        let bookmark = try BookmarkManager().recreate(for: sourceDir)
        let site = ManagedSite(name: "Coordinator", folderBookmark: bookmark)
        let coordinator = BuildCoordinator()
        defer {
            Task { @MainActor in await coordinator.stop() }
            // Clean the per-site output folder.
            try? FileManager.default.removeItem(
                at: BuildCoordinator.makeOutputURL(for: site.id)
            )
        }

        try await coordinator.start(site: site)
        XCTAssertEqual(coordinator.status, .watching)
        XCTAssertNotNil(coordinator.previewURL)
        XCTAssertNotNil(coordinator.lastReport)

        // Live preview should serve the rendered index.
        let url = coordinator.previewURL!.appendingPathComponent("index.html")
        let (initialBody, _) = try await URLSession.shared.data(from: url)
        XCTAssertTrue(
            String(decoding: initialBody, as: UTF8.self).contains("First")
        )

        // Mutate a source file → watcher fires → rebuild → second post visible.
        try """
            ---
            title: Second
            date: 2026-02-01
            ---

            Body two.
            """.write(
                to: sourceDir.appendingPathComponent("content/posts/second.md"),
                atomically: true,
                encoding: .utf8
            )

        let deadline = Date().addingTimeInterval(3.0)
        var sawSecond = false
        while Date() < deadline {
            let (body, _) = try await URLSession.shared.data(from: url)
            if String(decoding: body, as: UTF8.self).contains("Second") {
                sawSecond = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(sawSecond, "Rebuild after watcher fire never produced \"Second\"")
    }

    @MainActor
    func testStopReleasesResources() async throws {
        let bookmark = try BookmarkManager().recreate(for: sourceDir)
        let site = ManagedSite(name: "stoppable", folderBookmark: bookmark)
        let coordinator = BuildCoordinator()
        try await coordinator.start(site: site)
        XCTAssertNotNil(coordinator.previewURL)
        await coordinator.stop()
        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertNil(coordinator.previewURL)
    }

}
