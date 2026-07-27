import Foundation
import Observation

/// Account-scoped, persistent playlist-content index.
///
/// The first successful library sync fetches every playlist so artist/song counts
/// are authoritative. Later syncs compare provider revisions (Spotify snapshot
/// ids), track counts, and a fallback revalidation window, fetching only content
/// that may have changed. Detail views and the artist index share this repository,
/// so opening a playlist never starts over from an unrelated cache.
@MainActor
@Observable
final class PlaylistTracksRepository {
    private struct Entry: Codable, Sendable {
        var providerID: ProviderID
        var playlistID: String
        var contentRevision: String?
        var catalogTrackCount: Int
        var tracks: [UnifiedTrack]
        var loadedAt: Date
        var lastAccessedAt: Date
    }

    private struct Snapshot: Codable, Sendable {
        static let currentVersion = 1

        var version: Int
        var entries: [String: Entry]

        init(entries: [String: Entry]) {
            version = Self.currentVersion
            self.entries = entries
        }
    }

    private actor CacheIO {
        func load(from url: URL?) -> Snapshot? {
            guard let url, let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                  snapshot.version == Snapshot.currentVersion else { return nil }
            return snapshot
        }

        func save(_ snapshot: Snapshot, to url: URL?) {
            guard let url else { return }
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static var cacheURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
            .appendingPathComponent(
                AccountSessionStore.scopedFilename("playlist-tracks", ext: "json")
            )
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<[UnifiedTrack], Never>] = [:]
    private var lifecycleID = UUID()
    private var didHydrate = false
    private let cacheIO = CacheIO()

    private(set) var loadingKeys: Set<String> = []
    private(set) var refreshingKeys: Set<String> = []
    private(set) var failedKeys: Set<String> = []
    private(set) var synchronizing = false
    private(set) var completedSyncCount = 0
    private(set) var totalSyncCount = 0

    /// Providers without a content revision still get checked periodically. Track
    /// count changes are detected immediately by the catalog fetch; this window
    /// catches same-count replacements without hammering every playlist per launch.
    nonisolated static let unversionedRevalidationWindow: TimeInterval = 6 * 60 * 60
    /// A revision is authoritative, but a weekly safety pass protects against a
    /// provider returning a stuck or malformed token indefinitely.
    nonisolated static let versionedSafetyWindow: TimeInterval = 7 * 24 * 60 * 60

    func hydrate() async {
        guard !didHydrate else { return }
        didHydrate = true
        guard let snapshot = await cacheIO.load(from: Self.cacheURL) else { return }
        entries = snapshot.entries
    }

    func tracks(for playlist: UnifiedPlaylist) -> [UnifiedTrack] {
        entries[playlist.key]?.tracks ?? []
    }

    func hasResolved(_ playlist: UnifiedPlaylist) -> Bool {
        entries[playlist.key] != nil
    }

    func hasResolvedAll(_ playlists: [UnifiedPlaylist]) -> Bool {
        playlists.allSatisfy { entries[$0.key] != nil }
    }

    func cachedContents(
        for playlists: [UnifiedPlaylist]
    ) -> [(playlist: UnifiedPlaylist, tracks: [UnifiedTrack])] {
        playlists.compactMap { playlist in
            guard let entry = entries[playlist.key] else { return nil }
            return (playlist, entry.tracks)
        }
    }

    func isInitiallyLoading(_ playlist: UnifiedPlaylist) -> Bool {
        loadingKeys.contains(playlist.key)
    }

    func isRefreshing(_ playlist: UnifiedPlaylist) -> Bool {
        refreshingKeys.contains(playlist.key)
    }

    func didFail(_ playlist: UnifiedPlaylist) -> Bool {
        failedKeys.contains(playlist.key)
    }

    /// Pure refresh policy kept internal so unit tests can cover the correctness
    /// boundary without filesystem or provider dependencies.
    nonisolated static func shouldRefresh(
        playlist: UnifiedPlaylist,
        cachedRevision: String?,
        cachedTrackCount: Int,
        loadedAt: Date,
        now: Date = Date(),
        force: Bool
    ) -> Bool {
        if force { return true }
        if playlist.trackCount != cachedTrackCount { return true }

        if let revision = playlist.contentRevision, !revision.isEmpty {
            if revision != cachedRevision { return true }
            return now.timeIntervalSince(loadedAt) >= versionedSafetyWindow
        }

        return now.timeIntervalSince(loadedAt) >= unversionedRevalidationWindow
    }

    /// Reconcile every known playlist with the persistent index. Missing entries
    /// are always loaded, making the first successful sync complete. Subsequent
    /// calls only schedule changed/stale entries and remove playlists no longer in
    /// the authoritative catalog.
    func synchronize(
        _ playlists: [UnifiedPlaylist],
        force: Bool = false,
        maxConcurrent: Int = 4
    ) async {
        await hydrate()

        let liveKeys = Set(playlists.map(\.key))
        let priorEntryCount = entries.count
        entries = entries.filter { liveKeys.contains($0.key) }
        let removedEntries = entries.count != priorEntryCount

        let now = Date()
        let candidates = playlists.filter { playlist in
            guard let cached = entries[playlist.key] else { return true }
            if cached.providerID != playlist.providerID
                || cached.playlistID != playlist.playlistID {
                return true
            }
            return Self.shouldRefresh(
                playlist: playlist,
                cachedRevision: cached.contentRevision,
                cachedTrackCount: cached.catalogTrackCount,
                loadedAt: cached.loadedAt,
                now: now,
                force: force
            )
        }

        guard !candidates.isEmpty else {
            if removedEntries { await persist() }
            return
        }

        synchronizing = true
        completedSyncCount = 0
        totalSyncCount = candidates.count
        defer {
            synchronizing = false
            completedSyncCount = 0
            totalSyncCount = 0
        }

        let requestLifecycleID = lifecycleID
        var nextIndex = 0
        var active: [(playlist: UnifiedPlaylist, task: Task<[UnifiedTrack], Never>)] = []
        let concurrency = max(1, maxConcurrent)

        func enqueueNext() {
            guard nextIndex < candidates.count else { return }
            let playlist = candidates[nextIndex]
            nextIndex += 1
            let task = beginFetch(playlist)
            active.append((playlist, task))
        }

        while active.count < concurrency, nextIndex < candidates.count {
            enqueueNext()
        }

        while !active.isEmpty {
            let job = active.removeFirst()
            let loaded = await job.task.value
            guard lifecycleID == requestLifecycleID else { return }
            apply(loaded, to: job.playlist)
            completedSyncCount += 1
            enqueueNext()
        }

        await persist()
    }

    func load(_ playlist: UnifiedPlaylist, force: Bool = false) async {
        await hydrate()
        let now = Date()

        if var cached = entries[playlist.key] {
            cached.lastAccessedAt = now
            entries[playlist.key] = cached
            if !Self.shouldRefresh(
                playlist: playlist,
                cachedRevision: cached.contentRevision,
                cachedTrackCount: cached.catalogTrackCount,
                loadedAt: cached.loadedAt,
                now: now,
                force: force
            ) {
                return
            }
        }

        let requestLifecycleID = lifecycleID
        let task = beginFetch(playlist)
        let loaded = await task.value
        guard lifecycleID == requestLifecycleID else { return }
        apply(loaded, to: playlist)
        await persist()
    }

    func reset() {
        lifecycleID = UUID()
        for task in inFlight.values { task.cancel() }
        entries = [:]
        inFlight = [:]
        loadingKeys = []
        refreshingKeys = []
        failedKeys = []
        synchronizing = false
        completedSyncCount = 0
        totalSyncCount = 0
        didHydrate = false
    }

    private func beginFetch(_ playlist: UnifiedPlaylist) -> Task<[UnifiedTrack], Never> {
        let key = playlist.key
        if let existing = inFlight[key] { return existing }

        if entries[key]?.tracks.isEmpty == false {
            refreshingKeys.insert(key)
        } else {
            loadingKeys.insert(key)
        }
        failedKeys.remove(key)

        let task = Task.detached(priority: .utility) {
            await Self.fetchTracks(for: playlist)
        }
        inFlight[key] = task
        return task
    }

    private func apply(_ loaded: [UnifiedTrack], to playlist: UnifiedPlaylist) {
        let key = playlist.key
        inFlight[key] = nil
        loadingKeys.remove(key)
        refreshingKeys.remove(key)

        // Adapters currently return [] for both failure and an empty playlist.
        // Positive catalog counts are unambiguously a failed read. For providers
        // without revisions/counts (notably MusicKit), preserve non-empty
        // last-good content rather than turning a transient failure into data loss.
        if loaded.isEmpty,
           playlist.trackCount > 0
            || (
                playlist.contentRevision == nil
                    && entries[key]?.tracks.isEmpty == false
                    && playlist.trackCount == 0
            ) {
            failedKeys.insert(key)
            return
        }

        let now = Date()
        let cachedTracksByKey = Dictionary(
            (entries[key]?.tracks ?? []).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let artworkPreserved = loaded.map {
            $0.preservingArtwork(from: cachedTracksByKey[$0.key])
        }
        entries[key] = Entry(
            providerID: playlist.providerID,
            playlistID: playlist.playlistID,
            contentRevision: playlist.contentRevision,
            catalogTrackCount: playlist.trackCount,
            tracks: artworkPreserved,
            loadedAt: now,
            lastAccessedAt: now
        )
        failedKeys.remove(key)
    }

    private func persist() async {
        await cacheIO.save(Snapshot(entries: entries), to: Self.cacheURL)
    }

    private nonisolated static func fetchTracks(
        for playlist: UnifiedPlaylist
    ) async -> [UnifiedTrack] {
        if playlist.isMixtape {
            guard let id = UUID(uuidString: playlist.playlistID),
                  let detail = await BackendAPI.shared.getMixtape(id: id) else { return [] }
            return detail.tracks.map(mapMixtapeTrack)
        }
        let provider = ProviderRegistry.provider(for: playlist.providerID)
        let first = await provider
            .playlistTracks(playlist.playlistID)
        guard first.isEmpty, playlist.trackCount > 0 else { return first }

        // One short retry smooths over token refresh/rate-limit races during the
        // initial bounded fan-out without turning a persistent provider failure
        // into an endless loading loop.
        try? await Task.sleep(for: .milliseconds(450))
        return await provider.playlistTracks(playlist.playlistID)
    }

    private nonisolated static func mapMixtapeTrack(_ track: MixtapeTrackDTO) -> UnifiedTrack {
        let parts = track.trackUri.split(separator: ":")
        let providerID = ProviderID(rawValue: String(parts.first ?? "spotify")) ?? .spotify
        let providerTrackID = String(parts.last ?? "")
        let artist = track.artist ?? ""
        return UnifiedTrack(
            key: track.trackUri,
            providerID: providerID,
            providerTrackID: providerTrackID,
            uri: track.trackUri,
            name: track.trackName ?? "",
            artists: [UnifiedArtist(id: artist, name: artist)],
            album: nil,
            albumArt: URL(string: track.albumArt ?? ""),
            durationMs: track.durationMs ?? 0
        )
    }
}
