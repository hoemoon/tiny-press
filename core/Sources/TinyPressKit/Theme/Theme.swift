import Foundation

/// A pair of HTML layouts and static assets distributed as a single folder.
public struct Theme: Sendable, Equatable {
    /// Theme identifier — matches the directory name.
    public let name: String

    /// Absolute URL of the theme's root folder. Contains `theme.json`,
    /// `layouts/`, and `assets/`.
    public let rootURL: URL

    /// Decoded `theme.json` metadata.
    public let metadata: ThemeMetadata

    public init(name: String, rootURL: URL, metadata: ThemeMetadata) {
        self.name = name
        self.rootURL = rootURL
        self.metadata = metadata
    }

    /// Path to the layouts folder.
    public var layoutsURL: URL { rootURL.appendingPathComponent("layouts", isDirectory: true) }

    /// Path to the assets folder.
    public var assetsURL: URL { rootURL.appendingPathComponent("assets", isDirectory: true) }

    /// File URL for a named layout (e.g. `"post"` → `layouts/post.html`).
    public func layoutURL(for layoutName: String) -> URL {
        layoutsURL.appendingPathComponent(layoutName).appendingPathExtension("html")
    }

    /// All files within the assets folder. Empty when `assets/` is missing.
    public func assetURLs() -> [URL] {
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: assetsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                urls.append(url)
            }
        }
        return urls
    }
}

/// `theme.json` schema.
public struct ThemeMetadata: Codable, Sendable, Equatable {
    /// Theme display name.
    public var name: String
    /// Theme version (semver).
    public var version: String
    /// Optional author / credits string.
    public var author: String?
    /// Map from `Page.Kind` raw value (`"post"`, `"page"`, `"index"`) to the
    /// layout file name (without extension) to use by default.
    public var defaultLayouts: [String: String]

    public init(
        name: String,
        version: String,
        author: String? = nil,
        defaultLayouts: [String: String] = [:]
    ) {
        self.name = name
        self.version = version
        self.author = author
        self.defaultLayouts = defaultLayouts
    }
}

/// Errors raised while loading a theme.
public enum ThemeError: Error, Sendable {
    /// `theme.json` was not found at `themePath`.
    case missingMetadata(themeName: String)
    /// The named built-in theme is not bundled with the kit.
    case unknownBuiltinTheme(name: String)
    /// The requested layout file does not exist.
    case missingLayout(layoutName: String, themeName: String)
}
