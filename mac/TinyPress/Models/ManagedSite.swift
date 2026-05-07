import Foundation

/// Persisted record for a folder the user has registered with the app.
///
/// `folderBookmark` is a security-scoped bookmark — the only way an
/// App-Sandbox process can re-acquire access to a user-picked folder
/// across launches.
struct ManagedSite: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var folderBookmark: Data
    var lastBuildAt: Date?
    var lastBuildSucceeded: Bool
    var previewPort: Int?

    init(
        id: UUID = UUID(),
        name: String,
        folderBookmark: Data,
        lastBuildAt: Date? = nil,
        lastBuildSucceeded: Bool = false,
        previewPort: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.folderBookmark = folderBookmark
        self.lastBuildAt = lastBuildAt
        self.lastBuildSucceeded = lastBuildSucceeded
        self.previewPort = previewPort
    }
}
