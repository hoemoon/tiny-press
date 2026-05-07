import Foundation

/// Top-level entry point for converting a content folder into a static site.
public final class SiteBuilder: Sendable {
    private let frontmatterParser: FrontmatterParser
    private let markdownRenderer: MarkdownRenderer

    public init() {
        self.frontmatterParser = FrontmatterParser()
        self.markdownRenderer = MarkdownRenderer()
    }

    /// Run the full build pipeline.
    ///
    /// - Parameters:
    ///   - sourceRoot: Folder containing `tinypress.yml`, `content/`, `static/`.
    ///   - outputRoot: Folder where the rendered site will be written.
    ///   - cleanOutput: When `true` (default) the output folder is wiped
    ///     before writing, except for dot-prefixed entries (e.g. `.git`).
    ///   - includeDrafts: When `true`, posts with `draft: true` are included.
    public func build(
        sourceRoot: URL,
        outputRoot: URL,
        cleanOutput: Bool = true,
        includeDrafts: Bool = false
    ) async throws -> BuildReport {
        let start = Date()
        var warnings: [String] = []

        let configURL = sourceRoot.appendingPathComponent("tinypress.yml")
        let config: SiteConfig
        if FileManager.default.fileExists(atPath: configURL.path) {
            config = try SiteConfig.load(from: configURL)
        } else {
            warnings.append("tinypress.yml not found — using defaults")
            config = .default
        }

        let theme = try resolveTheme(config: config, sourceRoot: sourceRoot)

        if cleanOutput {
            try cleanOutputDirectory(outputRoot)
        }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let pages = try discoverPages(
            in: sourceRoot,
            config: config,
            includeDrafts: includeDrafts,
            warnings: &warnings
        )
        try assertNoSlugCollisions(pages: pages)

        let site = Site(
            config: config,
            sourceRoot: sourceRoot,
            outputRoot: outputRoot,
            pages: pages
        )

        let renderer = TemplateRenderer(theme: theme)
        var generated = 0
        for page in site.pages {
            try writePage(page, in: site, renderer: renderer)
            generated += 1
        }

        // Index page is rendered separately when no `content/index.md` exists,
        // OR when one exists but should still receive the post-list layout.
        let hasUserIndex = site.pages.contains { $0.kind == .index }
        if !hasUserIndex {
            let html = try renderer.renderIndex(site: site, includeDrafts: includeDrafts)
            let indexURL = outputRoot.appendingPathComponent("index.html")
            try html.data(using: .utf8)!.write(to: indexURL)
            generated += 1
        }

        let copier = AssetCopier()
        let themeAssetCount = try copier.copyTree(
            from: theme.assetsURL,
            to: outputRoot.appendingPathComponent("assets")
        )
        let userAssetCount = try copier.copyTree(
            from: sourceRoot.appendingPathComponent("static"),
            to: outputRoot
        )

        return BuildReport(
            pagesGenerated: generated,
            assetsCopied: themeAssetCount + userAssetCount,
            duration: Date().timeIntervalSince(start),
            warnings: warnings
        )
    }

    // MARK: Theme resolution

    private func resolveTheme(config: SiteConfig, sourceRoot: URL) throws -> Theme {
        // Treat values that look like a path as relative to the site root.
        if config.theme.contains("/") || config.theme.hasPrefix(".") {
            let url = URL(fileURLWithPath: config.theme, relativeTo: sourceRoot).standardized
            return try Theme.load(from: url)
        }
        if BuiltinThemes.names.contains(config.theme) {
            return try BuiltinThemes.load(named: config.theme)
        }
        // Allow a sibling `themes/<name>` override under the source root.
        let local = sourceRoot
            .appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent(config.theme, isDirectory: true)
        if FileManager.default.fileExists(atPath: local.path) {
            return try Theme.load(from: local)
        }
        throw ThemeError.unknownBuiltinTheme(name: config.theme)
    }

    // MARK: Discovery

    private func discoverPages(
        in sourceRoot: URL,
        config: SiteConfig,
        includeDrafts: Bool,
        warnings: inout [String]
    ) throws -> [Page] {
        let contentRoot = sourceRoot.appendingPathComponent("content", isDirectory: true)
        guard FileManager.default.fileExists(atPath: contentRoot.path) else {
            return []
        }

        var pages: [Page] = []
        guard
            let enumerator = FileManager.default.enumerator(
                at: contentRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            do {
                let page = try makePage(
                    fileURL: url,
                    contentRoot: contentRoot,
                    config: config
                )
                if !includeDrafts && page.frontmatter.draft { continue }
                pages.append(page)
            } catch {
                warnings.append("Skipped \(url.lastPathComponent): \(error)")
            }
        }
        return pages.sorted { $0.relativePath < $1.relativePath }
    }

    private func makePage(
        fileURL: URL,
        contentRoot: URL,
        config: SiteConfig
    ) throws -> Page {
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let (frontmatter, body) = try frontmatterParser.parse(raw)

        let relative = relativePath(of: fileURL, against: contentRoot)
        let kind = inferKind(relativePath: relative)
        let bodyHTML = markdownRenderer.render(body)

        var page = Page(
            sourceURL: fileURL,
            relativePath: relative,
            kind: kind,
            frontmatter: frontmatter,
            bodyMarkdown: body,
            bodyHTML: bodyHTML
        )
        page.permalink = makePermalink(for: page, config: config)
        return page
    }

    private func inferKind(relativePath: String) -> Page.Kind {
        let parts = relativePath.split(separator: "/").map(String.init)
        if parts.count == 1 && parts[0].lowercased() == "index.md" {
            return .index
        }
        if parts.first?.lowercased() == "posts" {
            return .post
        }
        return .page
    }

    private func makePermalink(for page: Page, config: SiteConfig) -> String {
        switch page.kind {
        case .index:
            return "/"
        case .post:
            switch config.permalinkStyle {
            case .pretty: return "/posts/\(page.slug)/"
            case .file: return "/posts/\(page.slug).html"
            }
        case .page:
            switch config.permalinkStyle {
            case .pretty: return "/\(page.slug)/"
            case .file: return "/\(page.slug).html"
            }
        }
    }

    // MARK: Writing

    private func writePage(_ page: Page, in site: Site, renderer: TemplateRenderer) throws {
        let html = try renderer.render(page: page, in: site)
        let outputURL = pageOutputURL(for: page, in: site)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try html.data(using: .utf8)!.write(to: outputURL)
    }

    private func pageOutputURL(for page: Page, in site: Site) -> URL {
        switch site.config.permalinkStyle {
        case .pretty:
            // Strip leading `/`, append `index.html` for a folder-style URL.
            let trimmed = page.permalink.hasPrefix("/")
                ? String(page.permalink.dropFirst()) : page.permalink
            let base = trimmed.hasSuffix("/")
                ? trimmed + "index.html"
                : trimmed + "/index.html"
            return site.outputRoot.appendingPathComponent(base)
        case .file:
            let trimmed = page.permalink.hasPrefix("/")
                ? String(page.permalink.dropFirst()) : page.permalink
            return site.outputRoot.appendingPathComponent(trimmed)
        }
    }

    private func relativePath(of url: URL, against root: URL) -> String {
        // `/tmp` is a symlink to `/private/tmp` on macOS, so we resolve both
        // sides before comparing. Without this, an enumerator-produced URL
        // (`/private/tmp/...`) doesn't share a prefix with a user-provided
        // root (`/tmp/...`).
        let rootComponents = root.resolvingSymlinksInPath().standardized.pathComponents
        let urlComponents = url.resolvingSymlinksInPath().standardized.pathComponents
        guard urlComponents.count >= rootComponents.count else { return url.lastPathComponent }
        return urlComponents[rootComponents.count...].joined(separator: "/")
    }

    // MARK: Validation

    private func assertNoSlugCollisions(pages: [Page]) throws {
        var seen: [String: String] = [:]
        for page in pages {
            let key = "\(page.kind.rawValue):\(page.slug)"
            if let existing = seen[key] {
                throw BuildError.duplicateSlug(
                    slug: page.slug,
                    firstPath: existing,
                    secondPath: page.relativePath
                )
            }
            seen[key] = page.relativePath
        }
    }

    // MARK: Cleaning

    private func cleanOutputDirectory(_ outputRoot: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: outputRoot.path) else { return }
        let contents = try fm.contentsOfDirectory(atPath: outputRoot.path)
        for entry in contents {
            if entry.hasPrefix(".") { continue }
            try fm.removeItem(at: outputRoot.appendingPathComponent(entry))
        }
    }
}

/// Summary of a `SiteBuilder.build` run.
public struct BuildReport: Sendable, Equatable {
    /// Number of pages written, including the auto-generated index when one
    /// exists.
    public let pagesGenerated: Int
    /// Total static asset files copied (theme + user `static/`).
    public let assetsCopied: Int
    /// Wall-clock duration of the build.
    public let duration: TimeInterval
    /// Non-fatal issues encountered (e.g. malformed pages, missing config).
    public let warnings: [String]

    public init(pagesGenerated: Int, assetsCopied: Int, duration: TimeInterval, warnings: [String]) {
        self.pagesGenerated = pagesGenerated
        self.assetsCopied = assetsCopied
        self.duration = duration
        self.warnings = warnings
    }
}

/// Errors raised by `SiteBuilder.build`.
public enum BuildError: Error, Sendable {
    /// Two pages of the same kind collided on slug.
    case duplicateSlug(slug: String, firstPath: String, secondPath: String)
}
