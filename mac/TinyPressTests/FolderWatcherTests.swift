import XCTest

@testable import TinyPress

final class FolderWatcherTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    @MainActor
    func testFiresOnceForBurstOfWrites() async throws {
        let watcher = FolderWatcher(url: workDir, debounceInterval: 0.2)
        defer { watcher.stop() }

        let counter = ChangeCounter()
        try watcher.start { Task { await counter.increment() } }

        // Let FSEvents register the watch before we hit it.
        try await Task.sleep(nanoseconds: 200_000_000)

        for i in 0..<10 {
            try Data("\(i)".utf8).write(
                to: workDir.appendingPathComponent("burst-\(i).md")
            )
        }

        try await Task.sleep(nanoseconds: 1_500_000_000)
        let calls = await counter.value
        XCTAssertGreaterThanOrEqual(calls, 1)
        XCTAssertLessThanOrEqual(calls, 3, "Debounce should coalesce the burst")
    }

    @MainActor
    func testIgnoresOutputFolderChanges() async throws {
        let watcher = FolderWatcher(
            url: workDir,
            debounceInterval: 0.2,
            ignoredComponents: ["_site"]
        )
        defer { watcher.stop() }

        let counter = ChangeCounter()
        try watcher.start { Task { await counter.increment() } }

        try await Task.sleep(nanoseconds: 200_000_000)

        let outDir = workDir.appendingPathComponent("_site", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outDir, withIntermediateDirectories: true
        )
        for i in 0..<5 {
            try Data("\(i)".utf8).write(
                to: outDir.appendingPathComponent("f-\(i).html")
            )
        }

        try await Task.sleep(nanoseconds: 1_000_000_000)
        let calls = await counter.value
        // Note: FSEvents may still fire because creating `_site` itself is
        // a change in the watched root. The directory creation event isn't
        // filtered by component, but writes inside it are. The important
        // assertion is that we don't get a flood proportional to the
        // number of files.
        XCTAssertLessThanOrEqual(calls, 1, "Output folder writes must not loop us back in")
    }
}

private actor ChangeCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
