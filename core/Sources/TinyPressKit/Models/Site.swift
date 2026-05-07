import Foundation

/// Root build-time context. Populated incrementally by `SiteBuilder`.
public struct Site: Sendable {
    /// Site-wide configuration loaded from `tinypress.yml`.
    public let config: SiteConfig

    /// Root folder containing `tinypress.yml`, `content/`, `static/`.
    public let sourceRoot: URL

    /// Output folder where the static site is written.
    public let outputRoot: URL

    /// Pages discovered and processed during the build.
    public var pages: [Page]

    /// Static asset paths (under `static/`) earmarked for copying.
    public var assets: [URL]

    public init(
        config: SiteConfig,
        sourceRoot: URL,
        outputRoot: URL,
        pages: [Page] = [],
        assets: [URL] = []
    ) {
        self.config = config
        self.sourceRoot = sourceRoot
        self.outputRoot = outputRoot
        self.pages = pages
        self.assets = assets
    }

    /// Posts (kind == .post), filtered by draft status, sorted by date desc.
    public func posts(includeDrafts: Bool = false) -> [Page] {
        pages
            .filter { $0.kind == .post }
            .filter { includeDrafts || !$0.frontmatter.draft }
            .sorted { left, right in
                let leftDate = left.frontmatter.date ?? .distantPast
                let rightDate = right.frontmatter.date ?? .distantPast
                return leftDate > rightDate
            }
    }
}
