import Foundation
import Testing
@testable import TinyPressKit

@Suite("Theme")
struct ThemeTests {
    @Test func loadsBuiltinDefaultTheme() throws {
        let theme = try BuiltinThemes.default
        #expect(theme.name == "default")
        #expect(theme.metadata.defaultLayouts["post"] == "post")
    }

    @Test func unknownBuiltinThemeThrows() {
        #expect(throws: ThemeError.self) {
            _ = try BuiltinThemes.load(named: "nonexistent")
        }
    }

    @Test func rendersPagePassesThroughContent() throws {
        let theme = try BuiltinThemes.default
        let renderer = TemplateRenderer(theme: theme)

        let page = Page(
            sourceURL: URL(fileURLWithPath: "/tmp/about.md"),
            relativePath: "pages/about.md",
            kind: .page,
            frontmatter: Frontmatter(title: "About"),
            bodyMarkdown: "# About",
            bodyHTML: "<h1>About</h1>",
            permalink: "/about/"
        )
        let site = Site(
            config: .default,
            sourceRoot: URL(fileURLWithPath: "/tmp/in"),
            outputRoot: URL(fileURLWithPath: "/tmp/out"),
            pages: [page]
        )
        let html = try renderer.render(page: page, in: site)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<h1>About</h1>"))
        #expect(html.contains("About · Untitled Site"))
    }

    @Test func rendersIndexWithPostList() throws {
        let theme = try BuiltinThemes.default
        let renderer = TemplateRenderer(theme: theme)

        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: "2026-01-01T00:00:00Z")!
        var fm = Frontmatter(title: "Hello")
        fm.date = date

        let post = Page(
            sourceURL: URL(fileURLWithPath: "/tmp/posts/2026-01-01-hello.md"),
            relativePath: "posts/2026-01-01-hello.md",
            kind: .post,
            frontmatter: fm,
            bodyMarkdown: "Hello body",
            bodyHTML: "<p>Hello body</p>",
            permalink: "/posts/hello/"
        )
        let site = Site(
            config: .default,
            sourceRoot: URL(fileURLWithPath: "/tmp/in"),
            outputRoot: URL(fileURLWithPath: "/tmp/out"),
            pages: [post]
        )
        let html = try renderer.renderIndex(site: site)
        #expect(html.contains("/posts/hello/"))
        #expect(html.contains("Hello"))
    }

    @Test func defaultThemeAssetURLsIncludeStyle() throws {
        let theme = try BuiltinThemes.default
        let assetNames = theme.assetURLs().map { $0.lastPathComponent }
        #expect(assetNames.contains("style.css"))
    }

    @Test func defaultThemeLayoutURLPointsAtFile() throws {
        let theme = try BuiltinThemes.default
        let url = theme.layoutURL(for: "post")
        #expect(url.lastPathComponent == "post.html")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func loadFromFolderFailsWhenMetadataMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: ThemeError.self) {
            _ = try Theme.load(from: dir)
        }
    }

    @Test func missingLayoutThrows() throws {
        let theme = try BuiltinThemes.default
        let renderer = TemplateRenderer(theme: theme)

        var fm = Frontmatter()
        fm.layout = "nonexistent"
        let page = Page(
            sourceURL: URL(fileURLWithPath: "/tmp/x.md"),
            relativePath: "pages/x.md",
            kind: .page,
            frontmatter: fm,
            bodyMarkdown: "",
            bodyHTML: "",
            permalink: "/x/"
        )
        let site = Site(
            config: .default,
            sourceRoot: URL(fileURLWithPath: "/tmp"),
            outputRoot: URL(fileURLWithPath: "/tmp/out"),
            pages: [page]
        )
        #expect(throws: ThemeError.self) {
            _ = try renderer.render(page: page, in: site)
        }
    }
}
