import AppKit
import Foundation
import Observation
import TinyPressKit

/// Top-level app state.
///
/// Built on the new Swift Observation framework — AppKit views subscribe via
/// `withObservationTracking` (see Task 2.7).  Stays on the `MainActor` so UI
/// observers can read state without further hopping.
@MainActor
@Observable
final class AppState {
    private(set) var sites: [ManagedSite] = []
    private(set) var activePreview: ManagedSite.ID?
    private(set) var loadError: String?

    private let store: SiteStore

    init(store: SiteStore = SiteStore()) {
        self.store = store
    }

    /// Reload the persisted site list. Called on launch.
    func refresh() async {
        do {
            self.sites = try await store.loadAll()
            self.loadError = nil
        } catch {
            self.sites = []
            self.loadError = "\(error)"
        }
    }

    /// Add a folder to the list and persist.
    /// - Parameters:
    ///   - folderBookmark: Security-scoped bookmark for the folder
    ///     (created by `BookmarkManager` in Task 2.3).
    ///   - name: User-facing display name.
    @discardableResult
    func addSite(folderBookmark: Data, name: String) async throws -> ManagedSite {
        let site = ManagedSite(name: name, folderBookmark: folderBookmark)
        self.sites = try await store.add(site)
        return site
    }

    /// Remove the site with `id` and persist. Stops the active preview if
    /// it was for this site.
    func removeSite(id: UUID) async {
        if activePreview == id { activePreview = nil }
        do {
            self.sites = try await store.remove(id: id)
        } catch {
            self.loadError = "\(error)"
        }
    }

    let coordinator = BuildCoordinator()

    /// Begin watching + serving the site at `id`. Stops any previous
    /// preview so only one site is active at a time.
    func startPreview(id: UUID) async {
        guard let site = sites.first(where: { $0.id == id }) else { return }
        await coordinator.stop()
        do {
            try await coordinator.start(site: site)
            activePreview = id
        } catch {
            loadError = "\(error)"
            activePreview = nil
        }
    }

    /// Stop any active preview.
    func stopPreview() async {
        await coordinator.stop()
        activePreview = nil
    }

    /// Release resources held during the app session. Called from
    /// `applicationWillTerminate`.
    func shutdown() async {
        await stopPreview()
    }
}
