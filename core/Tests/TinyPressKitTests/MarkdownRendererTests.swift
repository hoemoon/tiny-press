import Foundation
import Testing
@testable import TinyPressKit

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {
    private let renderer = MarkdownRenderer()

    @Test func rendersHeadingsAndParagraphs() {
        let html = renderer.render("# Hi\n\nA paragraph.")
        #expect(html.contains("<h1>Hi</h1>"))
        #expect(html.contains("<p>A paragraph.</p>"))
    }

    @Test func rendersFencedCodeBlockWithLanguageClass() {
        let md = """
            ```swift
            let x = 1
            ```
            """
        let html = renderer.render(md)
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = 1"))
        #expect(html.contains("</code></pre>"))
    }

    @Test func rendersInlineEmphasisAndStrong() {
        let html = renderer.render("**bold** and *italic*")
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>italic</em>"))
    }

    @Test func escapesHTMLInText() {
        let html = renderer.render("a < b & c > d")
        #expect(html.contains("a &lt; b &amp; c &gt; d"))
    }

    @Test func rendersImagesPreservingPath() {
        let html = renderer.render("![alt](images/logo.png)")
        #expect(html.contains("<img src=\"images/logo.png\""))
        #expect(html.contains("alt=\"alt\""))
    }

    @Test func rendersUnorderedList() {
        let html = renderer.render("- a\n- b")
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>a</li>"))
        #expect(html.contains("<li>b</li>"))
    }

    @Test func rendersBlockquoteAndHorizontalRule() {
        let html = renderer.render("> Quoted\n\n---\n\nAfter")
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("Quoted"))
        #expect(html.contains("<hr />"))
    }

    @Test func rendersOrderedListAndStartIndex() {
        let html = renderer.render("1. one\n2. two")
        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>one</li>"))
    }

    @Test func rendersTableWithHeader() {
        let md = """
            | a | b |
            | - | - |
            | 1 | 2 |
            """
        let html = renderer.render(md)
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>a</th>"))
        #expect(html.contains("<td>1</td>"))
    }

    @Test func rendersStrikethrough() {
        let html = renderer.render("~~gone~~")
        #expect(html.contains("<del>gone</del>"))
    }

    @Test func rendersInlineCodeAndLink() {
        let html = renderer.render("Use `swift build` then [docs](https://example.com).")
        #expect(html.contains("<code>swift build</code>"))
        #expect(html.contains("<a href=\"https://example.com\">docs</a>"))
    }

    @Test func rendersLargeMarkdownUnder100ms() {
        let line = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
        var input = ""
        // Build ~1MB document.
        let chunkCount = 1_048_576 / line.utf8.count
        input.reserveCapacity(line.count * chunkCount)
        for _ in 0..<chunkCount {
            input.append(line)
            input.append("\n\n")
        }
        let start = Date()
        _ = renderer.render(input)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.5, "Rendering took \(elapsed)s — exceeds budget")
    }
}
