#if os(macOS)
import XCTest

@testable import TinyPressKit

final class PreviewServerTests: XCTestCase {
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try Data(
            "<html><head><title>Hi</title></head><body><h1>Hi</h1></body></html>".utf8
        )
        .write(to: workDir.appendingPathComponent("index.html"))
        try Data("body { color: black; }".utf8)
            .write(to: workDir.appendingPathComponent("style.css"))
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    func testServesIndexHTMLAndInjectsLiveReloadScript() async throws {
        let server = PreviewServer(rootDirectory: workDir, preferredPort: 18_080)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let url = URL(string: "http://127.0.0.1:\(port)/")!
        let (data, response) = try await fetch(url: url)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(body.contains("<h1>Hi</h1>"))
        XCTAssertTrue(body.contains("/__tinypress_reload"))
    }

    func testNonHTMLResponseIsNotRewritten() async throws {
        let server = PreviewServer(rootDirectory: workDir, preferredPort: 18_180)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let url = URL(string: "http://127.0.0.1:\(port)/style.css")!
        let (data, _) = try await fetch(url: url)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(body.contains("__tinypress_reload"))
    }

    func testStartChoosesNextFreePortWhenPreferredIsBusy() async throws {
        let occupant = PreviewServer(rootDirectory: workDir, preferredPort: 18_280)
        let occupiedPort = try await occupant.start()
        defer { Task { await occupant.stop() } }

        let challenger = PreviewServer(rootDirectory: workDir, preferredPort: occupiedPort)
        let chosenPort = try await challenger.start()
        defer { Task { await challenger.stop() } }
        XCTAssertGreaterThan(chosenPort, occupiedPort)
    }

    private func fetch(url: URL) async throws -> (Data, URLResponse) {
        var config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        return try await session.data(from: url)
    }
}
#endif
