import Foundation

/// Account-scoped, device-local archive for completed recaps plus the last
/// generated current-week snapshot. The complete play ledger remains the source
/// of truth; a successful refresh replaces this cache rather than merging stale
/// weeks that may have been deleted from Listening History.
actor WeeklyRecapArchiveStore {
    struct Snapshot: Codable, Sendable, Equatable {
        static let currentVersion = 1

        let version: Int
        let ownerID: UUID
        let current: WeeklyRecap?
        let completed: [WeeklyRecap]
        let savedAt: Date
    }

    func load(ownerID: UUID) -> Snapshot? {
        guard let url = Self.cacheURL(ownerID: ownerID),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == Snapshot.currentVersion,
              snapshot.ownerID == ownerID else {
            return nil
        }
        return snapshot
    }

    func replace(
        ownerID: UUID,
        current: WeeklyRecap,
        completed: [WeeklyRecap],
        savedAt: Date = Date()
    ) {
        guard let url = Self.cacheURL(ownerID: ownerID) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)

        let snapshot = Snapshot(
            version: Snapshot.currentVersion,
            ownerID: ownerID,
            current: current,
            completed: completed.sorted { $0.weekStart > $1.weekStart },
            savedAt: savedAt
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear(ownerID: UUID) {
        guard let url = Self.cacheURL(ownerID: ownerID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func cacheURL(ownerID: UUID) -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
            .appendingPathComponent(
                AccountSessionStore.scopedFilename(
                    "weekly-recaps",
                    ext: "json",
                    ownerID: ownerID
                )
            )
    }
}
