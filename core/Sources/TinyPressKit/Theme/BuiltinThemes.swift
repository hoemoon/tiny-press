import Foundation

/// Loaders for themes shipped inside `TinyPressKit.bundle`.
public enum BuiltinThemes {
    /// Names of built-in themes (folders under `Resources/themes/`).
    public static let names: [String] = ["default"]

    /// The opinionated "default" theme — minimal, content-first, dark-mode aware.
    public static var `default`: Theme {
        get throws { try load(named: "default") }
    }

    /// Load a built-in theme by name. Throws `ThemeError.unknownBuiltinTheme`
    /// if the name is not present in the bundle.
    public static func load(named name: String) throws -> Theme {
        guard names.contains(name) else {
            throw ThemeError.unknownBuiltinTheme(name: name)
        }
        let bundle = Bundle.module
        guard
            let resourceURL = bundle.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "themes"
            )
        else {
            throw ThemeError.unknownBuiltinTheme(name: name)
        }
        return try Theme.load(from: resourceURL)
    }
}

extension Theme {
    /// Load a theme from a folder on disk. `theme.json` must be present at
    /// the root.
    public static func load(from rootURL: URL) throws -> Theme {
        let metadataURL = rootURL.appendingPathComponent("theme.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw ThemeError.missingMetadata(themeName: rootURL.lastPathComponent)
        }
        let data = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(ThemeMetadata.self, from: data)
        return Theme(name: rootURL.lastPathComponent, rootURL: rootURL, metadata: metadata)
    }
}
