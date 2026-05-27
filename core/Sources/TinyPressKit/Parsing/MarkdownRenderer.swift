import Foundation
import Markdown

/// Renders CommonMark markdown to HTML using `swift-markdown`'s AST plus an
/// in-house `MarkupWalker` (`HTMLEmittingWalker`).
public struct MarkdownRenderer: Sendable {
    public init() {}

    /// Convert a markdown body to an HTML fragment.
    ///
    /// Image / link paths are preserved verbatim — relative paths are
    /// rewritten later by the build pipeline so the renderer stays
    /// orthogonal to URL routing concerns.
    public func render(_ markdown: String) -> String {
        let prepared = Self.escapeSingleTildes(markdown)
        let document = Document(parsing: prepared, options: [.parseBlockDirectives])
        var walker = HTMLEmittingWalker()
        walker.visit(document)
        return walker.html
    }

    /// `swift-markdown` always registers cmark-gfm's strikethrough
    /// extension, which is more permissive than the GFM spec: a single
    /// pair of `~` (e.g. `수십~수백`, `3,000~4,000`) is treated as
    /// strikethrough even though only `~~text~~` is meant to. Korean
    /// prose uses lone tildes for numeric / lexical ranges constantly,
    /// so we escape any single tilde to `\~` before parsing. Double
    /// tildes are left alone so intentional strikethrough still works.
    static func escapeSingleTildes(_ markdown: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!~)~(?!~)"#)
        else { return markdown }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.stringByReplacingMatches(
            in: markdown,
            range: range,
            withTemplate: #"\\~"#
        )
    }
}
