import Foundation

/// Persistence layer for the registered-sites list.
///
/// Stored as JSON at `~/Library/Application Support/TinyPress/sites.json`.
/// Implemented as an `actor` so disk I/O can be awaited from any actor
/// without races.
actor SiteStore {
    private let storeURL: URL
    private let backupURL: URL
    private let fileManager: FileManager

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let baseDir = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.storeURL = baseDir.appendingPathComponent("sites.json")
        self.backupURL = baseDir.appendingPathComponent("sites.backup.json")
    }

    /// Read the persisted list. A corrupted main file is reported but does
    /// not throw — the backup is consulted, and failing that an empty list
    /// is returned so the app can still launch.
    func loadAll() async throws -> [ManagedSite] {
        guard fileManager.fileExists(atPath: storeURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storeURL)
            return try decode(data)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path) {
                let data = try Data(contentsOf: backupURL)
                return (try? decode(data)) ?? []
            }
            return []
        }
    }

    /// Atomically replace the persisted list. The previous content is
    /// rotated to `sites.backup.json` first.
    func save(_ sites: [ManagedSite]) async throws {
        try ensureDirectoryExists()
        if fileManager.fileExists(atPath: storeURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: storeURL, to: backupURL)
        }
        let data = try encode(sites)
        try data.write(to: storeURL, options: [.atomic])
    }

    /// Append a single site and persist.
    func add(_ site: ManagedSite) async throws -> [ManagedSite] {
        var current = try await loadAll()
        if let existing = current.firstIndex(where: { $0.id == site.id }) {
            current[existing] = site
        } else {
            current.append(site)
        }
        try await save(current)
        return current
    }

    /// Remove a site by id and persist. Returns the surviving list.
    @discardableResult
    func remove(id: UUID) async throws -> [ManagedSite] {
        var current = try await loadAll()
        current.removeAll { $0.id == id }
        try await save(current)
        return current
    }

    // MARK: Helpers

    private func ensureDirectoryExists() throws {
        let dir = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func decode(_ data: Data) throws -> [ManagedSite] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ManagedSite].self, from: data)
    }

    private func encode(_ sites: [ManagedSite]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sites)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("TinyPress", isDirectory: true)
    }
}
