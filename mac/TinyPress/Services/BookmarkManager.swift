import AppKit
import Foundation

/// Errors surfaced by `BookmarkManager`.
enum BookmarkError: Error {
    /// The bookmark resolves but is stale; caller should `recreate(for:)`.
    case stale
    /// `NSOpenPanel` was dismissed without a selection.
    case userCancelled
    /// `startAccessingSecurityScopedResource()` returned false.
    case accessDenied
    /// Bookmark blob could not be decoded.
    case decodingFailed(Error)
}

/// Wraps `NSOpenPanel` plus security-scoped bookmark create / resolve.
///
/// Sandboxed apps lose access to user-picked folders the moment the
/// process exits unless we serialise a `withSecurityScope` bookmark and
/// resolve it on the next launch. Callers must balance every successful
/// `resolve(...)` with `stopAccessing(_:)` once they're done with the URL.
struct BookmarkManager: Sendable {
    init() {}

    /// Show an `NSOpenPanel` configured for picking a single folder.
    /// Returns the picked URL plus a fresh security-scoped bookmark blob.
    @MainActor
    func pickFolder(prompt: String = "Choose folder") async throws -> (url: URL, bookmark: Data) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = prompt
        panel.title = prompt

        let response = await panel.beginAsModal()
        guard response == .OK, let url = panel.url else {
            throw BookmarkError.userCancelled
        }
        let bookmark = try recreate(for: url)
        return (url, bookmark)
    }

    /// Resolve a bookmark blob back to a URL.
    /// - Returns: `(url, isStale)` — when `isStale` is true callers should
    ///   call `recreate(for:)` and replace the stored bookmark.
    func resolve(bookmark: Data) throws -> (URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            throw BookmarkError.decodingFailed(error)
        }
    }

    /// Begin accessing a previously-resolved URL. The caller MUST balance
    /// this with `stopAccessing(_:)` — failing to do so leaks file-access
    /// resources back to the sandbox daemon.
    func beginAccessing(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }
    }

    /// Stop accessing a URL previously passed to `beginAccessing(_:)`.
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    /// Build a fresh `withSecurityScope` bookmark for a URL the user just
    /// granted access to (e.g. via `NSOpenPanel`).
    func recreate(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

extension NSOpenPanel {
    /// Async shim around `beginSheetModal(for:completionHandler:)` style
    /// modal presentation.
    @MainActor
    fileprivate func beginAsModal() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            self.begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}
