import Foundation

/// Codable on-disk snapshot of the master library, persisted as JSON in
/// Application Support so the library shows instantly on launch and survives
/// offline / a transient provider failure. Load and save run off the main actor
/// (the struct is `Sendable`); a version tag lets a future schema change discard
/// an incompatible file cleanly instead of crashing.
struct MasterLibrarySnapshot: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var savedAt: Date
    var tracks: [MasterTrack]
    var artists: [MasterArtist]

    init(tracks: [MasterTrack], artists: [MasterArtist], savedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.savedAt = savedAt
        self.tracks = tracks
        self.artists = artists
    }

    // MARK: - Location

    private static var directory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
    }

    private static func fileURL(ownerID: UUID?) -> URL? {
        directory?.appendingPathComponent(
            AccountSessionStore.scopedFilename(
                "master-library",
                ext: "json",
                ownerID: ownerID
            )
        )
    }

    // MARK: - Persistence

    /// Read + decode the snapshot, discarding a version-mismatched or corrupt file.
    /// Runs on the shared cache actor so it never overlaps another library decode.
    static func load(ownerID: UUID?) async -> MasterLibrarySnapshot? {
        guard let ownerID,
              let snapshot = await LibraryCacheIO.shared.load(Self.self, from: fileURL(ownerID: ownerID)),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    /// Encode + atomically write on the shared cache actor. Best-effort: never
    /// throws to the caller.
    func save(ownerID: UUID?) async {
        guard let ownerID else { return }
        await LibraryCacheIO.shared.save(self, to: Self.fileURL(ownerID: ownerID))
    }
}
