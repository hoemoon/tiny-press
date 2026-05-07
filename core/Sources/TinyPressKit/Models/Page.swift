import Foundation

/// A single processed page in the site graph.
public struct Page: Sendable, Equatable {
    /// Absolute URL of the source `.md` file.
    public let sourceURL: URL

    /// Path of the source file relative to `content/`.
    public let relativePath: String

    /// Classification used to pick a default layout and routing prefix.
    public let kind: Kind

    /// Parsed frontmatter (title, tags, etc.).
    public let frontmatter: Frontmatter

    /// Markdown body with the frontmatter block stripped.
    public let bodyMarkdown: String

    /// Rendered HTML body — populated by `MarkdownRenderer`.
    public var bodyHTML: String

    /// Final URL path (e.g. `/posts/hello/`).
    public var permalink: String

    /// Page kind used to dispatch templates and routing.
    public enum Kind: String, Sendable, Codable, Equatable {
        case post, page, index
    }

    public init(
        sourceURL: URL,
        relativePath: String,
        kind: Kind,
        frontmatter: Frontmatter,
        bodyMarkdown: String,
        bodyHTML: String = "",
        permalink: String = ""
    ) {
        self.sourceURL = sourceURL
        self.relativePath = relativePath
        self.kind = kind
        self.frontmatter = frontmatter
        self.bodyMarkdown = bodyMarkdown
        self.bodyHTML = bodyHTML
        self.permalink = permalink
    }

    /// Slug derived from `frontmatter.slug` or the source filename.
    public var slug: String {
        if let custom = frontmatter.slug, !custom.isEmpty { return custom }
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return Page.normalizeSlug(stem)
    }

    /// Effective title — uses frontmatter, falls back to the slug humanised.
    public var title: String {
        frontmatter.title ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func normalizeSlug(_ raw: String) -> String {
        // Strip a leading `YYYY-MM-DD-` prefix commonly used in post filenames
        // so it doesn't bleed into the URL.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePrefix = #/^(\d{4})-(\d{2})-(\d{2})-/#
        if let match = try? datePrefix.firstMatch(in: trimmed) {
            return String(trimmed[match.range.upperBound...])
        }
        return trimmed
    }
}
