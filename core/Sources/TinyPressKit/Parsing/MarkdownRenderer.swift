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
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var walker = HTMLEmittingWalker()
        walker.visit(document)
        return walker.html
    }
}
