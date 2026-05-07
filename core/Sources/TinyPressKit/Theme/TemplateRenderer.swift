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

    private func makeExcerpt(from markdown: String, limit: Int = 160) -> String {
        let stripped = markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }) ?? ""
        if stripped.count <= limit { return stripped }
        let endIndex = stripped.index(stripped.startIndex, offsetBy: limit)
        return String(stripped[..<endIndex]).trimmingCharacters(in: .whitespaces) + "…"
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
