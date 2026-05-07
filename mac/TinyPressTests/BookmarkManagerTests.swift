import XCTest

@testable import TinyPress

final class BookmarkManagerTests: XCTestCase {
    func testRecreateAndResolveRoundTripForLocalFolder() throws {
        let manager = BookmarkManager()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-bookmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let blob = try manager.recreate(for: dir)
        XCTAssertFalse(blob.isEmpty)

        let (resolved, isStale) = try manager.resolve(bookmark: blob)
        XCTAssertEqual(
            resolved.resolvingSymlinksInPath().standardized,
            dir.resolvingSymlinksInPath().standardized
        )
        XCTAssertFalse(isStale)
    }

    func testResolveOnGarbageBlobThrows() {
        let manager = BookmarkManager()
        let garbage = Data(repeating: 0xFF, count: 32)
        XCTAssertThrowsError(try manager.resolve(bookmark: garbage))
    }
}
