import Foundation
import Testing
@testable import TinyPressKit

@Suite("Models")
struct ModelTests {
    @Test func siteConfigDefault() {
        let config = SiteConfig.default
        #expect(config.theme == "default")
        #expect(config.language == "en")
        #expect(config.permalinkStyle == .pretty)
    }

    @Test func siteConfigRoundTrip() throws {
        let original = SiteConfig(
            title: "Hello",
            description: "desc",
            author: "me",
            baseURL: URL(string: "https://example.com"),
            theme: "default",
            language: "ko",
            permalinkStyle: .file
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SiteConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func frontmatterDefaultsForMissingFields() throws {
        let json = #"{"title":"Hello"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Frontmatter.self, from: data)
        #expect(decoded.title == "Hello")
        #expect(decoded.tags.isEmpty)
        #expect(decoded.draft == false)
        #expect(decoded.extra.isEmpty)
    }

    @Test func frontmatterDecodesExtraFields() throws {
        let json = """
        {"title":"X","extra":{"hero":"a.jpg","priority":3,"published":true,"keywords":["a","b"]}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Frontmatter.self, from: data)
        #expect(decoded.extra["hero"] == .string("a.jpg"))
        #expect(decoded.extra["priority"] == .int(3))
        #expect(decoded.extra["published"] == .bool(true))
        #expect(decoded.extra["keywords"] == .array([.string("a"), .string("b")]))
    }

    @Test func pageSlugStripsDatePrefix() {
        let url = URL(fileURLWithPath: "/tmp/2026-01-15-hello-world.md")
        let page = Page(
            sourceURL: url,
            relativePath: "posts/2026-01-15-hello-world.md",
            kind: .post,
            frontmatter: .empty,
            bodyMarkdown: ""
        )
        #expect(page.slug == "hello-world")
    }

    @Test func pageSlugRespectsCustomSlug() {
        let url = URL(fileURLWithPath: "/tmp/2026-01-15-hello-world.md")
        var fm = Frontmatter.empty
        fm.slug = "custom"
        let page = Page(
            sourceURL: url,
            relativePath: "posts/2026-01-15-hello-world.md",
            kind: .post,
            frontmatter: fm,
            bodyMarkdown: ""
        )
        #expect(page.slug == "custom")
    }

    @Test func sitePostsSortedByDateDescAndDraftsExcluded() {
        let url = URL(fileURLWithPath: "/tmp/x.md")
        let formatter = ISO8601DateFormatter()
        let early = formatter.date(from: "2026-01-01T00:00:00Z")!
        let late = formatter.date(from: "2026-02-01T00:00:00Z")!

        var earlyFM = Frontmatter.empty
        earlyFM.date = early
        var lateFM = Frontmatter.empty
        lateFM.date = late
        var draftFM = Frontmatter.empty
        draftFM.draft = true

        let pages: [Page] = [
            Page(sourceURL: url, relativePath: "p/early.md", kind: .post, frontmatter: earlyFM, bodyMarkdown: ""),
            Page(sourceURL: url, relativePath: "p/late.md", kind: .post, frontmatter: lateFM, bodyMarkdown: ""),
            Page(sourceURL: url, relativePath: "p/draft.md", kind: .post, frontmatter: draftFM, bodyMarkdown: ""),
        ]
        let site = Site(
            config: .default,
            sourceRoot: URL(fileURLWithPath: "/tmp"),
            outputRoot: URL(fileURLWithPath: "/tmp/out"),
            pages: pages
        )
        let posts = site.posts()
        #expect(posts.count == 2)
        #expect(posts.first?.relativePath == "p/late.md")
    }
}
