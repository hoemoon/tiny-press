import Foundation
import Yams

/// Top-level configuration loaded from `tinypress.yml` (or `site.yml`).
public struct SiteConfig: Codable, Sendable, Equatable {
    /// Site title used in `<title>` and headers.
    public var title: String

    /// Optional human-readable description; populates `<meta name="description">`.
    public var description: String?

    /// Optional author name surfaced in templates.
    public var author: String?

    /// Optional canonical deployment URL (e.g. `https://example.com`).
    public var baseURL: URL?

    /// Theme identifier — either the name of a built-in theme or a path to a
    /// theme folder relative to the site root.
    public var theme: String

    /// BCP-47 / ISO language code used in `<html lang>`.
    public var language: String

    /// Whether permalinks render as `/posts/slug/` (`pretty`) or
    /// `/posts/slug.html` (`file`).
    public var permalinkStyle: PermalinkStyle

    /// Search engine wired into the build (default: none).
    public var search: SearchConfig

    /// Permalink style options.
    public enum PermalinkStyle: String, Codable, Sendable, Equatable {
        /// `/posts/my-post/`
        case pretty
        /// `/posts/my-post.html`
        case file
    }

    public init(
        title: String,
        description: String? = nil,
        author: String? = nil,
        baseURL: URL? = nil,
        theme: String = "default",
        language: String = "en",
        permalinkStyle: PermalinkStyle = .pretty,
        search: SearchConfig = .none
    ) {
        self.title = title
        self.description = description
        self.author = author
        self.baseURL = baseURL
        self.theme = theme
        self.language = language
        self.permalinkStyle = permalinkStyle
        self.search = search
    }

    /// Safe defaults used by `tinypress init` and tests.
    public static let `default` = SiteConfig(
        title: "Untitled Site",
        description: nil,
        author: nil,
        baseURL: nil,
        theme: "default",
        language: "en",
        permalinkStyle: .pretty
    )

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Site"
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        self.baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        self.theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "default"
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        self.permalinkStyle =
            try container.decodeIfPresent(PermalinkStyle.self, forKey: .permalinkStyle) ?? .pretty
        self.search =
            try container.decodeIfPresent(SearchConfig.self, forKey: .search) ?? .none
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, author, baseURL, theme, language, permalinkStyle, search
    }

    /// Load a config from a YAML file.
    public static func load(from url: URL) throws -> SiteConfig {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SiteConfigError.invalidEncoding(url: url)
        }
        let decoder = YAMLDecoder()
        return try decoder.decode(SiteConfig.self, from: text)
    }

    /// Serialize this config to YAML at `url`. Atomic write.
    public func save(to url: URL) throws {
        let yaml = try YAMLEncoder().encode(self)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Errors raised while loading or validating a `SiteConfig`.
public enum SiteConfigError: Error, Sendable, Equatable {
    /// The file at `url` could not be decoded as UTF-8.
    case invalidEncoding(url: URL)
}

/// On-site search wiring. `engine: pagefind` runs the `pagefind` binary
/// against the build output after rendering and the default theme injects
/// the Pagefind UI on the index page. `engine: none` (default) skips both.
public struct SearchConfig: Codable, Sendable, Equatable {
    public var engine: Engine

    public enum Engine: String, Codable, Sendable, Equatable {
        case none
        case pagefind
    }

    public init(engine: Engine = .none) {
        self.engine = engine
    }

    public static let none = SearchConfig(engine: .none)
    public static let pagefind = SearchConfig(engine: .pagefind)

    public init(from decoder: Decoder) throws {
        // Allow either `search: pagefind` (shorthand string) or
        // `search: { engine: pagefind }` (full object) in YAML.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self),
           let parsed = Engine(rawValue: raw)
        {
            self.engine = parsed
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.engine = try container.decodeIfPresent(Engine.self, forKey: .engine) ?? .none
    }

    private enum CodingKeys: String, CodingKey { case engine }
}
