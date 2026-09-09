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
    static func load(
        ownerID: UUID? = AccountSessionStore.currentOwnerID
    ) -> MasterLibrarySnapshot? {
        guard let ownerID,
              let url = fileURL(ownerID: ownerID),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    /// Encode + atomically write. Creates the Application Support subfolder if
    /// needed. Best-effort: never throws to the caller.
    func save(ownerID: UUID? = AccountSessionStore.currentOwnerID) {
        guard let ownerID,
              let dir = Self.directory,
              let url = Self.fileURL(ownerID: ownerID) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
