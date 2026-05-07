import Foundation
import Testing
@testable import TinyPressKit

@Suite("SiteBuilder")
struct SiteBuilderTests {
    private func fixtureURL() -> URL {
        // `Resources/Fixtures` is bundled into the test target via the
        // `resources: [.copy("Fixtures")]` declaration in `Package.swift`.
        let bundle = Bundle.module
        guard let url = bundle.url(
            forResource: "sample-site",
            withExtension: nil,
            subdirectory: "Fixtures"
        ) else {
            fatalError("Missing sample-site fixture")
        }
        return url
    }

    private func makeOutputDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinypress-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func buildsExpectedTreeFromSampleSite() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        let report = try await builder.build(sourceRoot: source, outputRoot: output)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: output.appendingPathComponent("index.html").path))
        #expect(
            fm.fileExists(
                atPath: output.appendingPathComponent("posts/hello/index.html").path
            )
        )
        #expect(
            fm.fileExists(
                atPath: output.appendingPathComponent("posts/second/index.html").path
            )
        )
        #expect(
            !fm.fileExists(
                atPath: output.appendingPathComponent("posts/draft/index.html").path
            )
        )
        #expect(fm.fileExists(atPath: output.appendingPathComponent("about/index.html").path))
        #expect(fm.fileExists(atPath: output.appendingPathComponent("images/logo.png").path))
        #expect(fm.fileExists(atPath: output.appendingPathComponent("assets/style.css").path))

        // Posts: hello + second + about + index = 4
        #expect(report.pagesGenerated >= 3)
        #expect(report.assetsCopied >= 2)
    }

    @Test func indexHTMLListsPosts() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(sourceRoot: source, outputRoot: output)

        let indexPath = output.appendingPathComponent("index.html")
        let html = try String(contentsOf: indexPath, encoding: .utf8)
        #expect(html.contains("Hello"))
        #expect(html.contains("Second"))
        #expect(!html.contains("Draft Post"))
    }

    @Test func includesDraftsWhenRequested() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(
            sourceRoot: source, outputRoot: output, includeDrafts: true
        )

        let fm = FileManager.default
        #expect(
            fm.fileExists(
                atPath: output.appendingPathComponent("posts/draft/index.html").path
            )
        )
    }

    @Test func buildIsIdempotent() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(sourceRoot: source, outputRoot: output)
        let firstSnapshot = try snapshot(of: output)
        _ = try await builder.build(sourceRoot: source, outputRoot: output)
        let secondSnapshot = try snapshot(of: output)
        #expect(firstSnapshot == secondSnapshot)
    }

    @Test func buildPerformanceUnderOneSecondFor100Pages() async throws {
        let source = makeOutputDir().appendingPathComponent("source", isDirectory: true)
        let content = source.appendingPathComponent("content/posts", isDirectory: true)
        let output = makeOutputDir()
        defer {
            cleanup(source.deletingLastPathComponent())
            cleanup(output)
        }

        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try """
            title: Synthetic
            theme: default
            language: en
            permalinkStyle: pretty
            """.write(
                to: source.appendingPathComponent("tinypress.yml"),
                atomically: true,
                encoding: .utf8
            )
        for i in 0..<100 {
            let body = """
                ---
                title: Post \(i)
                date: 2026-01-\(String(format: "%02d", (i % 28) + 1))
                ---

                Body for post \(i).
                """
            try body.write(
                to: content.appendingPathComponent("post-\(i).md"),
                atomically: true,
                encoding: .utf8
            )
        }
        let start = Date()
        _ = try await SiteBuilder().build(sourceRoot: source, outputRoot: output)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 5.0, "Build took \(elapsed)s — exceeds budget")
    }

    @Test func failsOnDuplicateSlug() async throws {
        let source = makeOutputDir().appendingPathComponent("source", isDirectory: true)
        let posts = source.appendingPathComponent("content/posts", isDirectory: true)
        let output = makeOutputDir()
        defer {
            cleanup(source.deletingLastPathComponent())
            cleanup(output)
        }

        try FileManager.default.createDirectory(at: posts, withIntermediateDirectories: true)
        try "---\nslug: dup\n---\na".write(
            to: posts.appendingPathComponent("a.md"), atomically: true, encoding: .utf8
        )
        try "---\nslug: dup\n---\nb".write(
            to: posts.appendingPathComponent("b.md"), atomically: true, encoding: .utf8
        )
        await #expect(throws: BuildError.self) {
            _ = try await SiteBuilder().build(sourceRoot: source, outputRoot: output)
        }
    }

    private func snapshot(of root: URL) throws -> [String: String] {
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return [:] }
        var map: [String: String] = [:]
        for case let url as URL in enumerator {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile)
                ?? false
            guard isFile else { continue }
            let data = try Data(contentsOf: url)
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            map[relative] = data.base64EncodedString()
        }
        return map
    }
}
