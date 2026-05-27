import Foundation
import PathKit
import Stencil

/// Renders pages and indexes using the theme's Stencil layouts.
///
/// `TemplateRenderer` is the only place inside `TinyPressKit` that talks to
/// the Stencil API. If the engine is ever swapped out (e.g. for swift-mustache),
/// callers should not need to change.
public struct TemplateRenderer {
    /// Theme this renderer is bound to.
    public let theme: Theme

    private let environment: Environment

    public init(theme: Theme) {
        self.theme = theme
        self.environment = Self.makeEnvironment(theme: theme)
    }

    /// Render a single page (post / page / index) within the build context.
    public func render(page: Page, in site: Site) throws -> String {
        let layoutName = layoutFileName(for: page)
        let context = makeContext(for: page, site: site)
        do {
            return try environment.renderTemplate(name: layoutName, context: context)
        } catch _ as TemplateDoesNotExist {
            throw ThemeError.missingLayout(layoutName: layoutName, themeName: theme.name)
        } catch {
            throw error
        }
    }

    /// Render the site index (homepage / archive). Receives the post list
    /// pre-sorted by date desc.
    public func renderIndex(site: Site, includeDrafts: Bool = false) throws -> String {
        let layoutName = indexLayoutFileName()
        var context = makeBaseContext(site: site)
        context["page"] = [
            "title": site.config.title,
            "kind": "index",
            "permalink": "/",
        ]
        context["posts"] = site.posts(includeDrafts: includeDrafts).map { postDictionary(for: $0) }
        do {
            return try environment.renderTemplate(name: layoutName, context: context)
        } catch _ as TemplateDoesNotExist {
            throw ThemeError.missingLayout(layoutName: layoutName, themeName: theme.name)
        } catch {
            throw error
        }
    }

    // MARK: Environment

    /// Stencil's default `Environment` cannot resolve `{% extends %}` because
    /// it has no loader. We always wire up a `FileSystemLoader` rooted at the
    /// theme's `layouts/` folder.
    static func makeEnvironment(theme: Theme) -> Environment {
        let layoutsPath = Path(theme.layoutsURL.path)
        let loader = FileSystemLoader(paths: [layoutsPath])
        return Environment(
            loader: loader,
            extensions: [],
            templateClass: Template.self,
            trimBehaviour: .smart
        )
    }

    // MARK: Layout selection

    private func layoutFileName(for page: Page) -> String {
        if let custom = page.frontmatter.layout, !custom.isEmpty {
            return ensureHTMLSuffix(custom)
        }
        if let mapped = theme.metadata.defaultLayouts[page.kind.rawValue] {
            return ensureHTMLSuffix(mapped)
        }
        return ensureHTMLSuffix(page.kind.rawValue)
    }

    private func indexLayoutFileName() -> String {
        if let mapped = theme.metadata.defaultLayouts["index"] {
            return ensureHTMLSuffix(mapped)
        }
        return "index.html"
    }

    private func ensureHTMLSuffix(_ name: String) -> String {
        name.hasSuffix(".html") ? name : "\(name).html"
    }

    // MARK: Context building

    private func makeContext(for page: Page, site: Site) -> [String: Any] {
        var context = makeBaseContext(site: site)
        context["page"] = pageDictionary(for: page)
        context["content"] = page.bodyHTML
        // Index-kind pages share the index layout, so they need the post
        // list in context just like the auto-generated index.
        if page.kind == .index {
            context["posts"] = site.posts().map { postDictionary(for: $0) }
        }
        return context
    }

    private func makeBaseContext(site: Site) -> [String: Any] {
        var siteDict: [String: Any] = [
            "title": site.config.title,
            "language": site.config.language,
            "theme": site.config.theme,
        ]
        if let description = site.config.description { siteDict["description"] = description }
        if let author = site.config.author { siteDict["author"] = author }
        if let baseURL = site.config.baseURL { siteDict["baseURL"] = baseURL.absoluteString }
        siteDict["search"] = [
            "engine": site.config.search.engine.rawValue,
            "enabled": site.config.search.engine != .none,
        ]
        return ["site": siteDict]
    }

    private func pageDictionary(for page: Page) -> [String: Any] {
        var dict: [String: Any] = [
            "title": page.title,
            "kind": page.kind.rawValue,
            "permalink": page.permalink,
            "slug": page.slug,
            "tags": page.frontmatter.tags,
            "draft": page.frontmatter.draft,
        ]
        if let date = page.frontmatter.date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            dict["date"] = formatter.string(from: date)
            dict["dateISO"] = ISO8601DateFormatter().string(from: date)
        }
        if !page.frontmatter.extra.isEmpty {
            dict["extra"] = page.frontmatter.extra.mapValues(asAny)
        }
        return dict
    }

    private func postDictionary(for page: Page) -> [String: Any] {
        var dict = pageDictionary(for: page)
        dict["excerpt"] = makeExcerpt(from: page.bodyMarkdown)
        return dict
    }

    /// Returns a short plain-text excerpt suitable for a post-list card.
    ///
    /// Walks the body line by line, skipping markdown that doesn't read as
    /// prose (headings, images, horizontal rules, attribute-only emphasis,
    /// link-only lines), then joins the next 1–2 real prose lines and
    /// strips inline markdown so the surface text doesn't leak `**`, `[`,
    /// or stray image tags into the rendered card.
    private func makeExcerpt(from markdown: String, limit: Int = 220) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var collected: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if isExcerptSkippable(line) { continue }
            let clean = stripInlineMarkdown(line)
            if clean.isEmpty { continue }
            collected.append(clean)
            // Two prose lines is enough for a card preview — anything more
            // bloats the index page and competes with the title for
            // attention.
            if collected.count >= 2 { break }
        }
        let joined = collected.joined(separator: " ")
        if joined.count <= limit { return joined }
        let endIndex = joined.index(joined.startIndex, offsetBy: limit)
        return String(joined[..<endIndex]).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// True when a trimmed body line is markdown structure rather than
    /// readable prose. Headings, blank lines, dividers, lone images, list
    /// markers with no body text, and pure-emphasis "decorative" lines
    /// all qualify.
    private func isExcerptSkippable(_ line: String) -> Bool {
        if line.isEmpty { return true }
        if line.hasPrefix("#") { return true }
        if line.hasPrefix("---") || line.hasPrefix("***") { return true }
        if line.hasPrefix(">") { return true }
        if line.hasPrefix("```") { return true }
        // Image-only line: `![alt](src)` possibly wrapped in trailing
        // whitespace / stray closing parens (naverp output occasionally
        // produces these).
        if line.hasPrefix("!") { return true }
        // Lines that are purely asterisks / underscores used as visual
        // spacers in Naver Premium articles (`****`, `___`).
        let strippedOfMarkers =
            line.replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "_", with: "")
                .trimmingCharacters(in: .whitespaces)
        if strippedOfMarkers.isEmpty { return true }
        // Pure HTML comment lines.
        if line.hasPrefix("<!--") { return true }
        // Index / "related posts" lines: prose almost never carries two
        // or more `[text](url)` markdown links on the same line, but
        // index/TOC/관련글 lists do. Treat those as navigation rather
        // than excerpt material.
        if Self.countMarkdownLinks(in: line) >= 2 { return true }
        return false
    }

    private static func countMarkdownLinks(in line: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"\[[^\]]+\]\([^)]*\)"#)
        else { return 0 }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.numberOfMatches(in: line, range: range)
    }

    /// Removes a small set of inline markdown markers — emphasis,
    /// link syntax around the visible label, residual image markdown if
    /// it survived the line filter, and inline code backticks — so the
    /// excerpt reads as prose. Not a full markdown stripper; just enough
    /// to keep `**`, `[`, and `` ` `` out of the surface text.
    private func stripInlineMarkdown(_ line: String) -> String {
        var s = line
        // Drop inline images entirely (`![alt](url)`).
        if let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)]*\)"#) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        // Replace `[text](url)` with just `text`.
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]*\)"#) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
        }
        // Remove emphasis markers but keep the inner text.
        s = s
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        // Leading list markers (`- `, `* `, `1. `).
        if let regex = try? NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+\.)\s+"#) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func asAny(_ value: FrontmatterValue) -> Any {
        switch value {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map(asAny)
        case .dictionary(let v): return v.mapValues(asAny)
        case .null: return NSNull()
        }
    }
}
