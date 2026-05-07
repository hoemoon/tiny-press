import XCTest

@testable import TinyPress

final class SiteStoreTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinypress-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    func testEmptyStoreReturnsEmptyList() async throws {
        let store = SiteStore(directory: workDir)
        let sites = try await store.loadAll()
        XCTAssertEqual(sites, [])
    }

    func testAddPersistsAcrossInstances() async throws {
        let bookmark = Data([0x01, 0x02, 0x03])
        let site = ManagedSite(name: "Blog", folderBookmark: bookmark)

        let writer = SiteStore(directory: workDir)
        _ = try await writer.add(site)

        let reader = SiteStore(directory: workDir)
        let sites = try await reader.loadAll()
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(sites.first?.id, site.id)
        XCTAssertEqual(sites.first?.name, "Blog")
    }

    func testRemoveDropsEntry() async throws {
        let store = SiteStore(directory: workDir)
        let a = ManagedSite(name: "A", folderBookmark: Data([0x01]))
        let b = ManagedSite(name: "B", folderBookmark: Data([0x02]))
        _ = try await store.add(a)
        _ = try await store.add(b)
        let after = try await store.remove(id: a.id)
        XCTAssertEqual(after.map(\.name), ["B"])
    }

    func testCorruptedStoreFallsBackToBackup() async throws {
        let store = SiteStore(directory: workDir)
        let site = ManagedSite(name: "Backed up", folderBookmark: Data([0x01]))
        _ = try await store.add(site)
        // Save a second time so the previous version becomes the backup.
        _ = try await store.add(
            ManagedSite(name: "second", folderBookmark: Data([0x02]))
        )
        // Corrupt the main file. Backup still has both entries.
        let mainURL = workDir.appendingPathComponent("sites.json")
        try Data("not json".utf8).write(to: mainURL)

        let recovered = try await SiteStore(directory: workDir).loadAll()
        XCTAssertFalse(recovered.isEmpty, "Backup should hydrate state")
    }
}
