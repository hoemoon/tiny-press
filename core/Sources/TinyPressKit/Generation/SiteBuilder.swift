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

        // Flat-mode asset sidecars: in flat layout, each post may have a
        // sibling directory matching the source filename's basename (the
        // Obsidian "attachment folder" convention). Copy those into the
        // page's output directory so `./X` links resolve.
        var sidecarAssetCount = 0
        let contentRoot = resolveContentRoot(sourceRoot: sourceRoot)
        let isFlat = isFlatLayout(contentRoot: contentRoot)
        if isFlat {
            for page in site.pages where page.kind != .index {
                do {
                    sidecarAssetCount += try copyAssetSidecar(
                        for: page,
                        copier: copier,
                        site: site,
                        warnings: &warnings
                    )
                } catch {
                    warnings.append(
                        "Sidecar copy failed for \(page.sourceURL.lastPathComponent): \(error)"
                    )
                }
            }
        }

        let searchOutcome = await runSearchIndexer(
            site: site,
            warnings: &warnings
        )

        return BuildReport(
            pagesGenerated: generated,
            assetsCopied: themeAssetCount + userAssetCount + sidecarAssetCount,
            duration: Date().timeIntervalSince(start),
            warnings: warnings,
            searchIndex: searchOutcome
        )
    }

    /// Runs the configured search indexer over the freshly-built site.
    /// Failures are degraded to warnings — search wiring should never
    /// gate the rest of the build.
    private func runSearchIndexer(
        site: Site,
        warnings: inout [String]
    ) async -> BuildReport.SearchIndexStatus {
        switch site.config.search.engine {
        case .none:
            return .disabled
        case .pagefind:
            let runner = PagefindRunner()
            switch await runner.run(
                outputRoot: site.outputRoot,
                language: site.config.language
            ) {
            case .indexed:
                return .indexed(engine: "pagefind")
            case .binaryMissing:
                warnings.append(
                    "search.engine: pagefind — `pagefind` not found on PATH or via npx. "
                    + "Install it with `npm i -g pagefind`, `cargo install pagefind`, or set "
                    + "TINYPRESS_PAGEFIND to a binary path."
                )
                return .skipped(reason: "binary missing")
            case .failed(let status, let stderr):
                warnings.append(
                    "search.engine: pagefind exited with status \(status). "
                    + (stderr.isEmpty ? "" : "Output: \(stderr)")
                )
                return .skipped(reason: "exit \(status)")
            }
        }
    }

    private func copyAssetSidecar(
        for page: Page,
        copier: AssetCopier,
        site: Site,
        warnings: inout [String]
    ) throws -> Int {
        let basename = page.sourceURL.deletingPathExtension().lastPathComponent
        let sourceFolder = page.sourceURL.deletingLastPathComponent()
            .appendingPathComponent(basename, isDirectory: true)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceFolder.path, isDirectory: &isDir),
              isDir.boolValue
        else { return 0 }

        switch site.config.permalinkStyle {
        case .pretty:
            // Pretty permalinks output `<dir>/index.html`; assets land in
            // `<dir>/` next to the HTML so rewritten `./X` resolves.
            let outputDir = pageOutputURL(for: page, in: site)
                .deletingLastPathComponent()
            return try copier.copyTree(from: sourceFolder, to: outputDir)
        case .file:
            // File permalinks (`<slug>.html`) don't yet support sidecars
            // — image paths would have to stay `./<basename>/X` and the
            // folder would collide across siblings. Warn so users notice.
            warnings.append(
                "Asset sidecar for \(page.sourceURL.lastPathComponent) skipped — "
                + "file permalink style doesn't support flat-mode sidecars yet. "
                + "Switch to permalinkStyle: pretty in tinypress.yml."
            )
            return 0
        }
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

    /// Returns the directory we treat as the content root.
    ///
    /// Conventional sites have a dedicated ``content/`` subfolder. When
    /// that's missing — e.g. a naverp channel folder pointed at directly
    /// via ``--source`` — the source root itself is the content root.
    /// That lets `tinypress --source ~/Documents/Naverp/wave` build a
    /// site straight out of the archive without a wrapping directory.
    private func resolveContentRoot(sourceRoot: URL) -> URL {
        let candidate = sourceRoot.appendingPathComponent("content", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return sourceRoot
    }

    /// "Flat" content layout: no ``posts/`` or ``pages/`` subdirectories
    /// under the content root. Every ``.md`` at depth 1 is a content file,
    /// defaulting to ``post`` unless the frontmatter overrides it. This
    /// matches the naverp archive shape (``<channel>/<naver_id>.md``).
    private func isFlatLayout(contentRoot: URL) -> Bool {
        let fm = FileManager.default
        let postsDir = contentRoot.appendingPathComponent("posts", isDirectory: true)
        let pagesDir = contentRoot.appendingPathComponent("pages", isDirectory: true)
        var isDir: ObjCBool = false
        let hasPosts = fm.fileExists(atPath: postsDir.path, isDirectory: &isDir) && isDir.boolValue
        isDir = false
        let hasPages = fm.fileExists(atPath: pagesDir.path, isDirectory: &isDir) && isDir.boolValue
        return !hasPosts && !hasPages
    }

    private func discoverPages(
        in sourceRoot: URL,
        config: SiteConfig,
        includeDrafts: Bool,
        warnings: inout [String]
    ) throws -> [Page] {
        let contentRoot = resolveContentRoot(sourceRoot: sourceRoot)
        guard FileManager.default.fileExists(atPath: contentRoot.path) else {
            return []
        }
        let flat = isFlatLayout(contentRoot: contentRoot)

        let mdFiles: [URL]
        if flat {
            // Shallow walk — flat means flat. Subdirectories under the
            // content root in this mode are per-page asset folders, not
            // additional content.
            let entries = try FileManager.default.contentsOfDirectory(
                at: contentRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            mdFiles = entries.filter { $0.pathExtension.lowercased() == "md" }
        } else {
            guard let enumerator = FileManager.default.enumerator(
                at: contentRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            var files: [URL] = []
            for case let url as URL in enumerator
                where url.pathExtension.lowercased() == "md"
            {
                files.append(url)
            }
            mdFiles = files
        }

        var pages: [Page] = []
        for url in mdFiles {
            do {
                let page = try makePage(
                    fileURL: url,
                    contentRoot: contentRoot,
                    config: config,
                    flat: flat
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
        config: SiteConfig,
        flat: Bool
    ) throws -> Page {
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let (frontmatter, body) = try frontmatterParser.parse(raw)

        let relative = relativePath(of: fileURL, against: contentRoot)
        let kind = inferKind(
            relativePath: relative,
            frontmatter: frontmatter,
            flat: flat
        )
        let basename = fileURL.deletingPathExtension().lastPathComponent
        let normalizedBody = flat
            ? Self.rewriteSelfReferenceImages(body, basename: basename)
            : body
        let bodyHTML = markdownRenderer.render(normalizedBody)

        var page = Page(
            sourceURL: fileURL,
            relativePath: relative,
            kind: kind,
            frontmatter: frontmatter,
            bodyMarkdown: normalizedBody,
            bodyHTML: bodyHTML
        )
        page.permalink = makePermalink(for: page, config: config)
        return page
    }

    private func inferKind(
        relativePath: String,
        frontmatter: Frontmatter,
        flat: Bool
    ) -> Page.Kind {
        if relativePath.lowercased() == "index.md" {
            return .index
        }
        if let explicit = Self.parseExplicitKind(frontmatter.kind) {
            return explicit
        }
        if flat {
            return .post
        }
        if relativePath.hasPrefix("posts/") {
            return .post
        }
        return .page
    }

    /// Parse the optional ``kind:`` frontmatter field. Only `"post"` and
    /// `"page"` are valid; anything else (including `"index"`) is ignored
    /// so callers fall back to mode-based defaults.
    private static func parseExplicitKind(_ raw: String?) -> Page.Kind? {
        switch raw?.lowercased() {
        case "post": return .post
        case "page": return .page
        default: return nil
        }
    }

    /// In flat mode, the body markdown often references the sibling asset
    /// folder via ``![alt](./<basename>/file.png)`` — that's the Obsidian
    /// "attachment folder" convention. After build the assets are
    /// co-located with the rendered HTML under
    /// ``_site/posts/<slug>/file.png``, so the ``./<basename>/`` prefix
    /// becomes wrong. Rewrite to ``./file.png`` so the link resolves
    /// directly in the published page.
    static func rewriteSelfReferenceImages(_ body: String, basename: String) -> String {
        let escapedBase = NSRegularExpression.escapedPattern(for: basename)
        let pattern = "!\\[([^\\]]*)\\]\\(\\./\(escapedBase)/([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.stringByReplacingMatches(
            in: body,
            range: range,
            withTemplate: "![$1](./$2)"
        )
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
    /// Outcome of the search-indexing step (disabled when
    /// `search.engine == none`).
    public let searchIndex: SearchIndexStatus

    public enum SearchIndexStatus: Sendable, Equatable {
        case disabled
        case indexed(engine: String)
        case skipped(reason: String)
    }

    public init(
        pagesGenerated: Int,
        assetsCopied: Int,
        duration: TimeInterval,
        warnings: [String],
        searchIndex: SearchIndexStatus = .disabled
    ) {
        self.pagesGenerated = pagesGenerated
        self.assetsCopied = assetsCopied
        self.duration = duration
        self.warnings = warnings
        self.searchIndex = searchIndex
    }
}

/// Errors raised by `SiteBuilder.build`.
public enum BuildError: Error, Sendable {
    /// Two pages of the same kind collided on slug.
    case duplicateSlug(slug: String, firstPath: String, secondPath: String)
}
