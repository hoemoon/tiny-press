import Foundation

/// Copies static assets from theme `assets/` and the user `static/` folder
/// into the output tree.
struct AssetCopier {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Copy every regular file in `sourceRoot` into `destinationRoot`,
    /// preserving the folder hierarchy. Returns the number of files copied.
    /// Missing source folders are silently treated as empty.
    @discardableResult
    func copyTree(from sourceRoot: URL, to destinationRoot: URL) throws -> Int {
        guard fileManager.fileExists(atPath: sourceRoot.path) else { return 0 }

        try fileManager.createDirectory(
            at: destinationRoot, withIntermediateDirectories: true
        )

        var copied = 0
        guard
            let enumerator = fileManager.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey]
            )
            guard resourceValues.isRegularFile == true else { continue }

            let relative = relativePath(of: fileURL, against: sourceRoot)
            let target = destinationRoot.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: fileURL, to: target)
            copied += 1
        }
        return copied
    }

    private func relativePath(of url: URL, against root: URL) -> String {
        let rootComponents = root.resolvingSymlinksInPath().standardized.pathComponents
        let urlComponents = url.resolvingSymlinksInPath().standardized.pathComponents
        guard urlComponents.count >= rootComponents.count else { return url.lastPathComponent }
        let suffix = urlComponents[rootComponents.count...]
        return suffix.joined(separator: "/")
    }
}
