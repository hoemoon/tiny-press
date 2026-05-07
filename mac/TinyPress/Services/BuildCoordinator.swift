import AppKit
import Foundation
import Observation
import TinyPressKit

/// Glues `FolderWatcher`, `SiteBuilder`, and `PreviewServer` together for
/// a single registered site.
///
/// Output goes to `~/Library/Application Support/TinyPress/builds/<id>/`
/// rather than the user's source folder, so the user's tree stays clean
/// and the watcher can ignore the output location explicitly.
@MainActor
@Observable
final class BuildCoordinator {
    private(set) var status: Status = .idle
    private(set) var lastReport: BuildReport?
    private(set) var lastError: Error?
    private(set) var previewURL: URL?

    /// Tailscale Serve mirror of the local preview. Observed by the menu
    /// bar so the tailnet URL appears the moment it's ready.
    let tailscale: TailscaleServeAdapter

    enum Status: Equatable, Sendable {
        case idle, building, watching, error
    }

    private let bookmarkManager: BookmarkManager
    private let builder: SiteBuilder
    private var watcher: FolderWatcher?
    private var server: PreviewServer?

    private var sourceURL: URL?
    private var outputURL: URL?
    private var isAccessingScopedURL = false
    private var rebuildInFlight = false
    private var rebuildPending = false

    init(
        bookmarkManager: BookmarkManager = BookmarkManager(),
        builder: SiteBuilder = SiteBuilder(),
        tailscale: TailscaleServeAdapter = TailscaleServeAdapter()
    ) {
        self.bookmarkManager = bookmarkManager
        self.builder = builder
        self.tailscale = tailscale
    }

    /// Resolve the bookmark, kick off the first build, then wire up the
    /// watcher and the preview server.
    func start(site: ManagedSite) async throws {
        await stop()

        let (resolvedURL, isStale) = try bookmarkManager.resolve(bookmark: site.folderBookmark)
        if isStale {
            // Caller is responsible for persisting the refreshed bookmark
            // — `BuildCoordinator` only watches; `AppState.replaceSite`
            // (added in a later task) handles re-saving.
        }
        try bookmarkManager.beginAccessing(resolvedURL)
        isAccessingScopedURL = true
        sourceURL = resolvedURL

        let outputURL = Self.makeOutputURL(for: site.id)
        self.outputURL = outputURL

        // Build once before starting the watcher so the very first preview
        // request lands on something real.
        await runBuild()

        let server = PreviewServer(rootDirectory: outputURL)
        let port = try await server.start()
        self.server = server
        self.previewURL = URL(string: "http://127.0.0.1:\(port)/")

        // Probe + register with Tailscale Serve. Failures are non-fatal —
        // the local preview keeps working; the adapter surfaces the reason
        // via its `state` so the UI can show it.
        await tailscale.detect()
        await tailscale.enable(localPort: port)

        let watcher = FolderWatcher(url: resolvedURL, debounceInterval: 0.3)
        try watcher.start { [weak self] in
            Task { await self?.scheduleRebuild() }
        }
        self.watcher = watcher
        if status != .error { status = .watching }
    }

    /// Tear down the watcher and preview server, drop file-system access,
    /// and unregister Tailscale Serve.
    func stop() async {
        watcher?.stop()
        watcher = nil

        if let server {
            await server.stop()
        }
        server = nil
        previewURL = nil

        await tailscale.disable()

        if let url = sourceURL, isAccessingScopedURL {
            bookmarkManager.stopAccessing(url)
            isAccessingScopedURL = false
        }
        sourceURL = nil
        outputURL = nil
        status = .idle
        rebuildPending = false
    }

    /// Force a rebuild outside of a watcher event (e.g. menu action).
    func rebuild() async {
        await scheduleRebuild()
    }

    // MARK: Build pipeline

    private func scheduleRebuild() async {
        if rebuildInFlight {
            // Coalesce — if a build is in progress, just remember to run
            // again once it completes.
            rebuildPending = true
            return
        }
        await runBuild()
        if rebuildPending {
            rebuildPending = false
            await scheduleRebuild()
        }
    }

    private func runBuild() async {
        guard let sourceURL, let outputURL else { return }
        rebuildInFlight = true
        defer { rebuildInFlight = false }
        status = .building
        do {
            let report = try await builder.build(
                sourceRoot: sourceURL,
                outputRoot: outputURL
            )
            lastReport = report
            lastError = nil
            status = watcher == nil ? .idle : .watching
            server?.notifyClientsToReload()
        } catch {
            lastError = error
            status = .error
        }
    }

    // MARK: Output location

    static func makeOutputURL(for id: UUID) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("TinyPress", isDirectory: true)
            .appendingPathComponent("builds", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }
}
