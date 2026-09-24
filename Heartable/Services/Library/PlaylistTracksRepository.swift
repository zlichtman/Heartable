import CryptoKit
import UIKit
import Foundation
import Observation

/// The playlist-content index as the artist projection consumes it: every
/// distinct track once, and each playlist as a list of track keys. Nothing is
/// materialised per occurrence, so a song in forty playlists costs one track.
struct PlaylistIndexSnapshot: Sendable {
    let tracks: [String: UnifiedTrack]
    let occurrences: [(playlistKey: String, trackKeys: [String])]
}

/// Account-scoped, persistent playlist-content index.
///
/// The first successful library sync fetches every playlist so artist/song counts
/// are authoritative. Later syncs compare provider revisions (Spotify snapshot
/// ids), track counts, and a fallback revalidation window, fetching only content
/// that may have changed. Detail views and the artist index share this repository,
/// so opening a playlist never starts over from an unrelated cache.
///
/// Playlist content lives on disk. Startup restores a small metadata index;
/// opening a playlist reads its local file first, then revalidates through the
/// same scheduler as the background indexer. Only a bounded recent-screen cache
/// retains full playlist arrays. Artist indexing streams disk files one at a time.
@MainActor
@Observable
final class PlaylistTracksRepository {
    private struct Entry: Codable, Sendable {
        var providerID: ProviderID
        var playlistID: String
        var contentRevision: String?
        var catalogTrackCount: Int
        var storedTrackCount: Int
        var loadedAt: Date
        var lastAccessedAt: Date
    }

    /// One playlist on disk. Self-contained, so a missing or corrupt file loses
    /// that playlist alone and the next sync fetches it again.
    private struct PlaylistFile: Codable, Sendable {
        static let currentVersion = 2

        var version: Int
        var providerID: ProviderID
        var playlistID: String
        var contentRevision: String?
        var catalogTrackCount: Int
        var tracks: [UnifiedTrack]
        var loadedAt: Date
        var lastAccessedAt: Date
    }

    /// Small metadata manifest; full track arrays live in separate files.
    private struct IndexFile: Codable, Sendable {
        static let currentVersion = 3

        var version: Int
        var keys: [String]
        var entries: [String: Entry]? = nil
    }

    /// The single-file layout every build before the directory index wrote.
    private struct LegacyEntry: Codable, Sendable {
        var providerID: ProviderID
        var playlistID: String
        var contentRevision: String?
        var catalogTrackCount: Int
        var tracks: [UnifiedTrack]
        var loadedAt: Date
        var lastAccessedAt: Date
    }

    private struct Loaded: Sendable {
        var entries: [String: Entry]
    }

    nonisolated private static let defaultCacheRoot: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Heartable", isDirectory: true)

    nonisolated private static func directory(root: URL?, ownerID: UUID) -> URL? {
        root?.appendingPathComponent("playlist-tracks-\(ownerID.uuidString.lowercased())", isDirectory: true)
    }

    nonisolated private static func legacyURL(root: URL?, ownerID: UUID) -> URL? {
        root?.appendingPathComponent(
            AccountSessionStore.scopedFilename("playlist-tracks", ext: "json", ownerID: ownerID)
        )
    }

    nonisolated private static func indexURL(in directory: URL?) -> URL? {
        directory?.appendingPathComponent("index.json")
    }

    nonisolated static func fileName(for playlistKey: String) -> String {
        SHA256.hash(data: Data(playlistKey.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    nonisolated private static func fileURL(for playlistKey: String, in directory: URL?) -> URL? {
        directory?.appendingPathComponent(fileName(for: playlistKey))
    }

    private var entries: [String: Entry] = [:]
    private var resolved: [String: [UnifiedTrack]] = [:]
    @ObservationIgnored private var accessOrder: [String] = []
    @ObservationIgnored private var scheduler = SharedLoadScheduler<String, ProviderRead<UnifiedTrack>>(limit: 2)
    @ObservationIgnored private var loadTokens: [String: UUID] = [:]
    /// The disk index is authoritative. Only a few opened playlists are resident.
    private let maximumCachedTracks = 12_000
    private let maximumCachedPlaylists = 3
    private let temporaryOwnerID = UUID()
    private let fetch: @Sendable (UnifiedPlaylist) async -> ProviderRead<UnifiedTrack>
    /// Whether Spotify's persisted read cooldown is active. Only the live
    /// provider fetch shares it; injected test fetches never do by default.
    private let spotifyCooldownActive: @Sendable () async -> Bool
    private var lifecycleID = UUID()
    private var didHydrate = false
    private var hydratedOwnerID: UUID?
    private var hydrationTask: Task<Loaded?, Never>?
    private let cacheIO = LibraryCacheIO.shared
    private let cacheRoot: URL?
    private let persistenceEnabled: Bool
    private var memoryWarningObserver: (any NSObjectProtocol)?

    init(fetch: (@Sendable (UnifiedPlaylist) async -> ProviderRead<UnifiedTrack>)? = nil,
         persistenceEnabled: Bool = true,
         cacheRoot: URL? = nil,
         spotifyCooldownActive: (@Sendable () async -> Bool)? = nil) {
        self.fetch = fetch ?? Self.fetchTracks
        if let spotifyCooldownActive {
            self.spotifyCooldownActive = spotifyCooldownActive
        } else if fetch == nil {
            self.spotifyCooldownActive = { @Sendable in await SpotifyReadBackoff.shared.remaining() != nil }
        } else {
            self.spotifyCooldownActive = { @Sendable in false }
        }
        self.persistenceEnabled = persistenceEnabled
        self.cacheRoot = cacheRoot ?? (persistenceEnabled ? Self.defaultCacheRoot :
            FileManager.default.temporaryDirectory.appendingPathComponent("playlist-test-\(UUID())"))
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trimResolved(keeping: self?.accessOrder.last) }
        }
    }

    private(set) var loadingKeys: Set<String> = []
    private(set) var refreshingKeys: Set<String> = []
    private(set) var failedKeys: Set<String> = []
    private var failureMessages: [String: String] = [:]

    func failureMessage(for playlist: UnifiedPlaylist) -> String? { failureMessages[playlist.key] }
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

    /// Distinct tracks held in memory across every cached playlist.
    var debugUniqueTrackCount: Int { Set(resolved.values.flatMap { $0.map(\.key) }).count }
    var debugResidentTrackCount: Int { resolved.values.reduce(0) { $0 + $1.count } }
    /// Playlist rows, counting a song once per playlist it appears in.
    var debugOccurrenceCount: Int { entries.values.reduce(0) { $0 + $1.storedTrackCount } }

    func hydrate() async {
        guard let ownerID = AccountSessionStore.currentOwnerID ?? (persistenceEnabled ? nil : temporaryOwnerID) else { return }
        if didHydrate, hydratedOwnerID == ownerID { return }
        let requestID = lifecycleID

        let task: Task<Loaded?, Never>
        if let hydrationTask {
            task = hydrationTask
        } else {
            let io = cacheIO
            let root = cacheRoot
            task = Task.detached(priority: .userInitiated) {
                await Self.loadFromDisk(root: root, ownerID: ownerID, io: io)
            }
            hydrationTask = task
        }
        let loaded = await task.value
        guard lifecycleID == requestID,
              (AccountSessionStore.currentOwnerID ?? (persistenceEnabled ? nil : temporaryOwnerID)) == ownerID else { return }
        guard let loaded else { hydrationTask = nil; return }
        entries = loaded.entries
        resolved = [:]
        didHydrate = true
        hydratedOwnerID = ownerID
        hydrationTask = nil
    }

    /// Restores metadata only. Older layouts migrate one playlist at a time,
    /// preserving the source until the replacement manifest is committed.
    private nonisolated static func loadFromDisk(root: URL?, ownerID: UUID, io: LibraryCacheIO) async -> Loaded? {
        let directory = directory(root: root, ownerID: ownerID)
        let legacy = legacyURL(root: root, ownerID: ownerID)
        var loaded = Loaded(entries: [:])
        // A committed current manifest takes precedence over a legacy file kept
        // after an interrupted migration; never overwrite newer provider data.
        if let index = await io.load(IndexFile.self, from: indexURL(in: directory)),
           index.version == IndexFile.currentVersion, let entries = index.entries {
            loaded.entries = entries.filter { FileManager.default.fileExists(atPath: fileURL(for: $0.key, in: directory)!.path) }
            return loaded
        }

        if let legacy, FileManager.default.fileExists(atPath: legacy.path), let directory {
            // Convert one old playlist at a time into a staging directory. Never
            // delete the only valid cache after a disk-full/cancellation failure.
            let staging = directory.appendingPathExtension("migration")
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let migration = try await io.transformDictionary(at: legacy) { key, data in
                    try Task.checkCancellation()
                    let old = try JSONDecoder().decode(LegacyEntry.self, from: data)
                    let file = PlaylistFile(version: PlaylistFile.currentVersion, providerID: old.providerID,
                        playlistID: old.playlistID, contentRevision: old.contentRevision,
                        catalogTrackCount: old.catalogTrackCount, tracks: old.tracks,
                        loadedAt: old.loadedAt, lastAccessedAt: old.lastAccessedAt)
                    let encoded = try JSONEncoder().encode(file)
                    try encoded.write(to: fileURL(for: key, in: staging)!, options: .atomic)
                    return Entry(providerID: old.providerID, playlistID: old.playlistID,
                        contentRevision: old.contentRevision, catalogTrackCount: old.catalogTrackCount,
                        storedTrackCount: old.tracks.count, loadedAt: old.loadedAt, lastAccessedAt: old.lastAccessedAt)
                }
                guard let version = migration.fields["version"],
                      try JSONDecoder().decode(Int.self, from: version) == 1 else { throw JSONDictionaryStream.Failure.malformed }
                guard await io.save(IndexFile(version: IndexFile.currentVersion,
                    keys: Array(migration.entries.keys), entries: migration.entries),
                    to: indexURL(in: staging)) else { throw CocoaError(.fileWriteUnknown) }
                try Task.checkCancellation()
                // A completed directory wins on the next launch. The legacy file
                // survives until all files and the new manifest have landed.
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for key in migration.entries.keys {
                    let destination = fileURL(for: key, in: directory)!
                    let data = try Data(contentsOf: fileURL(for: key, in: staging)!, options: .mappedIfSafe)
                    try data.write(to: destination, options: .atomic)
                }
                guard await io.save(IndexFile(version: IndexFile.currentVersion,
                    keys: Array(migration.entries.keys), entries: migration.entries),
                    to: indexURL(in: directory)) else { throw CocoaError(.fileWriteUnknown) }
                await io.remove(at: legacy)
                await io.remove(at: staging)
            } catch {
                if Task.isCancelled { return nil }
                // Keep the original for recovery, but allow fresh provider reads
                // if the old document is corrupt or the migration cannot finish.
            }
        }

        guard let index = await io.load(IndexFile.self, from: indexURL(in: directory)),
              [2, IndexFile.currentVersion].contains(index.version) else { return loaded }
        if index.version == IndexFile.currentVersion, let entries = index.entries {
            loaded.entries = entries.filter { FileManager.default.fileExists(atPath: fileURL(for: $0.key, in: directory)!.path) }
            return loaded
        }
        for key in index.keys {
            if Task.isCancelled { return nil }
            guard let file = await io.load(PlaylistFile.self, from: fileURL(for: key, in: directory)),
                  file.version == PlaylistFile.currentVersion else { continue }
            loaded.entries[key] = Entry(
                providerID: file.providerID, playlistID: file.playlistID,
                contentRevision: file.contentRevision, catalogTrackCount: file.catalogTrackCount,
                storedTrackCount: file.tracks.count, loadedAt: file.loadedAt, lastAccessedAt: file.lastAccessedAt
            )
        }
        _ = await io.save(IndexFile(version: IndexFile.currentVersion, keys: Array(loaded.entries.keys), entries: loaded.entries), to: indexURL(in: directory))
        return loaded
    }

    /// Pure read during rendering; disk reads and cache mutation belong to load.
    func tracks(for playlist: UnifiedPlaylist) -> [UnifiedTrack] {
        resolved[playlist.key] ?? []
    }

    func hasLoaded(_ playlist: UnifiedPlaylist) -> Bool { resolved[playlist.key] != nil }
    func revision(for playlist: UnifiedPlaylist) -> String {
        "\(entries[playlist.key]?.loadedAt.timeIntervalSince1970 ?? 0)|\(resolved[playlist.key]?.count ?? -1)"
    }

    private func remember(_ tracks: [UnifiedTrack], key: String) {
        resolved[key] = tracks
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        while accessOrder.count > maximumCachedPlaylists || debugResidentTrackCount > maximumCachedTracks {
            guard accessOrder.count > 1 else { break }
            resolved[accessOrder.removeFirst()] = nil
        }
    }

    private func trimResolved(keeping key: String?) {
        resolved = resolved.filter { $0.key == key }
        accessOrder = accessOrder.filter { $0 == key }
    }

    func hasResolved(_ playlist: UnifiedPlaylist) -> Bool {
        entries[playlist.key] != nil
    }

    func hasResolvedAll(_ playlists: [UnifiedPlaylist]) -> Bool {
        playlists.allSatisfy { entries[$0.key] != nil }
    }

    /// Everything cached for these playlists, deduplicated by track key.
    func index(for playlists: [UnifiedPlaylist]) async -> PlaylistIndexSnapshot {
        let generation = lifecycleID
        var tracks: [String: UnifiedTrack] = [:]
        var occurrences: [(playlistKey: String, trackKeys: [String])] = []
        for playlist in playlists {
            guard !Task.isCancelled, generation == lifecycleID else {
                return PlaylistIndexSnapshot(tracks: [:], occurrences: [])
            }
            guard entries[playlist.key] != nil else { continue }
            guard let file = await readFile(playlist.key) else {
                // Let the next reconciliation repair this one missing/corrupt
                // file rather than considering its fresh metadata sufficient.
                guard generation == lifecycleID, !Task.isCancelled else { break }
                dropEntry(playlist.key)
                continue
            }
            for track in file.tracks { tracks[track.key] = track }
            occurrences.append((playlist.key, file.tracks.map(\.key)))
        }
        return PlaylistIndexSnapshot(tracks: tracks, occurrences: occurrences)
    }

    private func readFile(_ key: String) async -> PlaylistFile? {
        guard let target = persistTarget else { return nil }
        guard let file = await cacheIO.load(PlaylistFile.self, from: Self.fileURL(for: key, in: target.directory)),
              file.version == PlaylistFile.currentVersion else { return nil }
        return file
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
    /// the authoritative catalog. Each playlist is written to disk as it lands,
    /// and a cancelled caller stops the walk and the fetches it started.
    func synchronize(
        _ playlists: [UnifiedPlaylist],
        force: Bool = false,
        maxConcurrent: Int = 1
    ) async {
        let generation = lifecycleID
        await hydrate()
        guard !Task.isCancelled, generation == lifecycleID else { return }

        let liveKeys = Set(playlists.map(\.key))
        let stale = Set(entries.keys).subtracting(liveKeys)
        for key in stale { dropEntry(key) }
        if !stale.isEmpty { await persistRemoval(of: stale) }

        // During Spotify's Retry-After cooldown every Spotify read fails
        // instantly without a request. Walking hundreds of playlists would only
        // churn loading/failure state (and every screen observing it) in a
        // burst; leave them for the reconciliation after the cooldown.
        let spotifyCoolingDown = await spotifyCooldownActive()
        guard !Task.isCancelled, generation == lifecycleID else { return }
        let now = Date()
        let candidates = playlists.filter { playlist in
            if spotifyCoolingDown, playlist.providerID == .spotify { return false }
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
        if spotifyCoolingDown { MainThreadStallMonitor.note("playlist index: Spotify paused by rate limit") }
        guard !candidates.isEmpty else { return }

        synchronizing = true
        completedSyncCount = 0
        totalSyncCount = candidates.count
        MainThreadStallMonitor.note("playlist index start (\(candidates.count) of \(playlists.count))")
        defer {
            MainThreadStallMonitor.note("playlist index end (\(completedSyncCount)/\(candidates.count))")
            if generation == lifecycleID {
                synchronizing = false
                completedSyncCount = 0
                totalSyncCount = 0
            }
        }

        // Keep one slot available for a visible playlist. All callers share
        // the scheduler's global two-request budget.
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            func enqueue() {
                guard next < candidates.count, !Task.isCancelled else { return }
                let playlist = candidates[next]
                next += 1
                group.addTask { await self.load(playlist, force: force, visible: false) }
            }
            for _ in 0..<min(2, max(1, maxConcurrent)) { enqueue() }
            for await _ in group {
                guard generation == lifecycleID, !Task.isCancelled else { group.cancelAll(); return }
                completedSyncCount += 1
                enqueue()
            }
        }
    }

    func load(_ playlist: UnifiedPlaylist, force: Bool = false, visible: Bool = true) async {
        let generation = lifecycleID
        await hydrate()
        guard !Task.isCancelled, generation == lifecycleID else { return }
        // Local content is never queued behind network indexing.
        if visible, resolved[playlist.key] == nil, let file = await readFile(playlist.key),
           generation == lifecycleID, !Task.isCancelled {
            remember(file.tracks, key: playlist.key)
        }
        if visible, let resident = resolved[playlist.key], let cached = entries[playlist.key],
           !Self.shouldRefresh(playlist: playlist, cachedRevision: cached.contentRevision,
               cachedTrackCount: cached.catalogTrackCount, loadedAt: cached.loadedAt, force: force) {
            remember(resident, key: playlist.key)
            return
        }
        _ = await scheduler.value(for: playlist.key, priority: visible ? 1 : 0) { [weak self] in
            guard let self else { return .unavailable }
            return await self.performLoad(playlist, force: force, generation: generation)
        }
        guard visible, !Task.isCancelled, generation == lifecycleID else { return }
        if let cached = resolved[playlist.key] { remember(cached, key: playlist.key) }
        else if let file = await readFile(playlist.key), generation == lifecycleID, !Task.isCancelled {
            remember(file.tracks, key: playlist.key)
        }
    }

    private func performLoad(_ playlist: UnifiedPlaylist, force: Bool, generation: UUID) async -> ProviderRead<UnifiedTrack> {
        let key = playlist.key
        guard generation == lifecycleID, !Task.isCancelled else { return .unavailable }
        let cached = entries[key]
        if let cached, !Self.shouldRefresh(playlist: playlist, cachedRevision: cached.contentRevision,
            cachedTrackCount: cached.catalogTrackCount, loadedAt: cached.loadedAt, force: force),
            await readFile(key) != nil { return .success([]) }
        let token = UUID()
        loadTokens[key] = token
        // Every write to these observed collections notifies each screen that
        // reads any key, even when nothing changed, so skip no-op writes.
        if cached == nil { insert(key, into: \.loadingKeys) } else { insert(key, into: \.refreshingKeys) }
        remove(key, from: \.failedKeys)
        if failureMessages[key] != nil { failureMessages[key] = nil }
        defer {
            if loadTokens[key] == token {
                loadTokens[key] = nil
                remove(key, from: \.loadingKeys)
                remove(key, from: \.refreshingKeys)
            }
        }
        let result = await fetch(playlist)
        guard generation == lifecycleID, !Task.isCancelled else { return .unavailable }
        guard case .success(let loaded) = result else {
            insert(key, into: \.failedKeys)
            let message = result.failureMessage
            if failureMessages[key] != message { failureMessages[key] = message }
            return result
        }
        let old = await readFile(key)
        guard generation == lifecycleID, !Task.isCancelled, let target = persistTarget else { return .unavailable }
        let previous = Dictionary((old?.tracks ?? []).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = loaded.map { $0.preservingArtwork(from: previous[$0.key]) }
        let now = Date()
        let file = PlaylistFile(version: PlaylistFile.currentVersion, providerID: playlist.providerID,
            playlistID: playlist.playlistID, contentRevision: playlist.contentRevision,
            catalogTrackCount: playlist.trackCount, tracks: tracks, loadedAt: now, lastAccessedAt: now)
        guard await cacheIO.save(file, to: Self.fileURL(for: key, in: target.directory)) else {
            insert(key, into: \.failedKeys)
            return .unavailable
        }
        guard generation == lifecycleID, !Task.isCancelled else { return .unavailable }
        entries[key] = Entry(providerID: playlist.providerID, playlistID: playlist.playlistID,
            contentRevision: playlist.contentRevision, catalogTrackCount: playlist.trackCount,
            storedTrackCount: tracks.count, loadedAt: now, lastAccessedAt: now)
        // Indexing must not populate the screen cache; refresh a resident screen.
        if resolved[key] != nil { remember(tracks, key: key) }
        await persistIndex(target.directory)
        return .success([])
    }

    func readTransient(_ playlist: UnifiedPlaylist) async -> ProviderRead<UnifiedTrack> {
        let fetch = fetch
        return await scheduler.value(for: "friend:" + playlist.key, priority: 1) {
            await fetch(playlist)
        } ?? .unavailable
    }

    func remove(keys: Set<String>) async {
        guard !keys.isEmpty else { return }
        // Invalidate all outstanding publications; cancellation alone does not
        // stop an adapter from returning its already-fetched, now-deleted rows.
        lifecycleID = UUID()
        let previousScheduler = scheduler
        Task { await previousScheduler.cancelAll() }
        scheduler = SharedLoadScheduler(limit: 2)
        loadTokens = [:]
        loadingKeys = []
        refreshingKeys = []
        for key in keys {
            dropEntry(key)
            failedKeys.remove(key)
            failureMessages[key] = nil
        }
        await persistRemoval(of: keys)
    }

    func reset() {
        lifecycleID = UUID()
        hydrationTask?.cancel()
        let previousScheduler = scheduler
        Task { await previousScheduler.cancelAll() }
        scheduler = SharedLoadScheduler(limit: 2)
        loadTokens = [:]
        entries = [:]
        resolved = [:]
        accessOrder = []
        loadingKeys = []
        refreshingKeys = []
        failedKeys = []
        failureMessages = [:]
        synchronizing = false
        completedSyncCount = 0
        totalSyncCount = 0
        didHydrate = false
        hydratedOwnerID = nil
        hydrationTask = nil
    }

    private func dropEntry(_ key: String) {
        if entries[key] != nil { entries[key] = nil }
        if resolved[key] != nil { resolved[key] = nil }
        accessOrder.removeAll { $0 == key }
    }

    private func insert(_ key: String, into set: ReferenceWritableKeyPath<PlaylistTracksRepository, Set<String>>) {
        if !self[keyPath: set].contains(key) { self[keyPath: set].insert(key) }
    }

    private func remove(_ key: String, from set: ReferenceWritableKeyPath<PlaylistTracksRepository, Set<String>>) {
        if self[keyPath: set].contains(key) { self[keyPath: set].remove(key) }
    }

    private var persistTarget: (directory: URL?, ownerID: UUID)? {
        guard let ownerID = hydratedOwnerID,
              (AccountSessionStore.currentOwnerID ?? (persistenceEnabled ? nil : temporaryOwnerID)) == ownerID else { return nil }
        return (Self.directory(root: cacheRoot, ownerID: ownerID), ownerID)
    }

    private func persistRemoval(of keys: Set<String>) async {
        guard let target = persistTarget else { return }
        for key in keys { await cacheIO.remove(at: Self.fileURL(for: key, in: target.directory)) }
        await persistIndex(target.directory)
    }

    private func persistIndex(_ directory: URL?) async {
        await cacheIO.save(
            IndexFile(version: IndexFile.currentVersion, keys: Array(entries.keys), entries: entries),
            to: Self.indexURL(in: directory)
        )
    }

    private nonisolated static func fetchTracks(
        for playlist: UnifiedPlaylist
    ) async -> ProviderRead<UnifiedTrack> {
        if playlist.isMixtape {
            guard let id = UUID(uuidString: playlist.playlistID),
                  let detail = await BackendAPI.shared.getMixtape(id: id) else { return .unavailable }
            return .success(detail.tracks.map(mapMixtapeTrack))
        }
        let provider = ProviderRegistry.provider(for: playlist.providerID)
        return await provider.readPlaylistTracks(playlist.playlistID)
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
