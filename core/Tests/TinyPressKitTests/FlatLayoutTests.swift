import Foundation
import Testing
@testable import TinyPressKit

@Suite("FlatLayout")
struct FlatLayoutTests {
    private func fixtureURL() -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(
            forResource: "flat-site",
            withExtension: nil,
            subdirectory: "Fixtures"
        ) else {
            fatalError("Missing flat-site fixture")
        }
        return url
    }

    private func makeOutputDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinypress-flat-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func discoversFlatPostsWithoutContentSubdir() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(sourceRoot: source, outputRoot: output)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: output.appendingPathComponent("index.html").path))
        #expect(
            fm.fileExists(
                atPath: output.appendingPathComponent("posts/260124144615127ua/index.html").path
            )
        )
        #expect(
            fm.fileExists(
                atPath: output.appendingPathComponent("posts/260303233251216jo/index.html").path
            )
        )
    }

    @Test func kindPageInFrontmatterOptsOutOfListing() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(sourceRoot: source, outputRoot: output)

        let fm = FileManager.default
        // `about.md` declares `kind: page` — should land at `/about/`, not `/posts/about/`.
        #expect(fm.fileExists(atPath: output.appendingPathComponent("about/index.html").path))
        #expect(
            !fm.fileExists(atPath: output.appendingPathComponent("posts/about/index.html").path)
        )
    }

    @Test func indexExcludesPages() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(sourceRoot: source, outputRoot: output)

        let indexPath = output.appendingPathComponent("index.html")
        let html = try String(contentsOf: indexPath, encoding: .utf8)
        #expect(html.contains("화폐가 가고 실물이 지배하는 시대"))
        #expect(html.contains("[기초] 하락장에서 꺼내 읽는 투자의 원칙"))
        // About is a page (kind: page) — must not appear in the post list.
        #expect(!html.contains(">About<"))
    }

    @Test func copiesPerArticleAssetSidecar() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(sourceRoot: source, outputRoot: output)

        let fm = FileManager.default
        let assetBase = output
            .appendingPathComponent("posts/260124144615127ua")
        #expect(fm.fileExists(atPath: assetBase.appendingPathComponent("01.png").path))
        #expect(fm.fileExists(atPath: assetBase.appendingPathComponent("02.png").path))
        // The asset-less post should not produce an asset folder of its own
        // (only its index.html lives at posts/260303233251216jo/).
        let assetlessDir = output.appendingPathComponent("posts/260303233251216jo")
        let assetlessContents = (try? fm.contentsOfDirectory(atPath: assetlessDir.path)) ?? []
        #expect(assetlessContents == ["index.html"])
    }

    @Test func rewritesSelfReferenceImageLinks() async throws {
        let source = fixtureURL()
        let output = makeOutputDir()
        defer { cleanup(output) }

        let builder = SiteBuilder()
        _ = try await builder.build(sourceRoot: source, outputRoot: output)

        let postPath = output
            .appendingPathComponent("posts/260124144615127ua/index.html")
        let html = try String(contentsOf: postPath, encoding: .utf8)
        // The Obsidian-style `./260124.../01.png` should be rewritten to `./01.png`.
        #expect(html.contains("\"./01.png\""))
        #expect(html.contains("\"./02.png\""))
        #expect(!html.contains("./260124144615127ua/01.png"))
    }

    @Test func rewriteHelperPreservesUnrelatedLinks() {
        let basename = "260124144615127ua"
        let body = """
        Self image: ![](./260124144615127ua/01.png)
        Other post image: ![](./other-post/cover.jpg)
        Absolute path: ![](/images/banner.png)
        Remote: ![](https://example.com/x.png)
        """
        let out = SiteBuilder.rewriteSelfReferenceImages(body, basename: basename)
        #expect(out.contains("![](./01.png)"))
        #expect(out.contains("![](./other-post/cover.jpg)"))
        #expect(out.contains("![](/images/banner.png)"))
        #expect(out.contains("![](https://example.com/x.png)"))
        #expect(!out.contains("./260124144615127ua/"))
    }
}
