import Foundation
import Observation

/// Shared cache-first source for personal listening stats.
///
/// Every cached slice retains its source. Heartable slices contain only plays
/// Heartable actually observed; Spotify slices contain Spotify's own affinity
/// order. Provider libraries and global charts never enter this repository.
@MainActor
@Observable
final class TopTracksRepository {
    private struct SliceKey: Hashable {
        let range: StatRange
        let providerID: ProviderID
    }

    private struct ProviderSlice: Codable, Sendable, Equatable {
        let range: StatRange
        let providerID: ProviderID
        var tracks: [UnifiedTrack]
        var playCounts: [String: Int]?
        var fetchedAt: Date
    }

    private struct DiskSnapshot: Codable, Sendable {
        // Version 3 separates Heartable play counts from provider rankings.
        // Reject caches that merged unrelated sources.
        static let currentVersion = 3

        let version: Int
        let ownerID: UUID
        let slices: [ProviderSlice]
    }

    struct TrackStat: Sendable, Equatable {
        let track: UnifiedTrack
        let plays: Int
        let lastPlayedAt: Date
    }

    /// Serializes disk access so a slower, older encode can never overwrite a
    /// newer snapshot.
    private actor CacheIO {
        func load(from url: URL, ownerID: UUID) -> DiskSnapshot? {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(DiskSnapshot.self, from: data),
                  snapshot.version == DiskSnapshot.currentVersion,
                  snapshot.ownerID == ownerID else { return nil }
            return snapshot
        }

        func save(_ snapshot: DiskSnapshot, to url: URL) {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)

            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private var slices: [SliceKey: ProviderSlice] = [:]
    private var hydratedOwnerID: UUID?
    private var hydratingOwnerID: UUID?
    private var hydrationTask: Task<DiskSnapshot?, Never>?
    private var historyTask: Task<[PlayEntryDTO]?, Never>?
    private var historyEntries: [PlayEntryDTO] = []
    private var historyFetchedAt: Date?
    private var lifecycleID = UUID()
    private let cacheIO = CacheIO()

    private(set) var tracksByRange: [StatRange: [UnifiedTrack]] = [:]
    private(set) var playCountsByRange: [StatRange: [String: Int]] = [:]
    private(set) var lastUpdatedByRange: [StatRange: Date] = [:]
    private var initialLoadingSlices: Set<SliceKey> = []
    private var refreshingSlices: Set<SliceKey> = []

    /// Top-track rankings change slowly. A normal revisit inside this window is a
    /// memory/disk hit; pull-to-refresh always revalidates.
    private let freshnessWindow: TimeInterval = 5 * 60

    func tracks(for range: StatRange) -> [UnifiedTrack] {
        tracks(for: range, source: .heartable)
    }

    func tracks(
        for range: StatRange,
        source: TopTracksSource
    ) -> [UnifiedTrack] {
        slices[SliceKey(range: range, providerID: source.providerID)]?.tracks ?? []
    }

    func playCount(for track: UnifiedTrack, range: StatRange) -> Int {
        playCount(for: track, range: range, source: .heartable)
    }

    func playCount(
        for track: UnifiedTrack,
        range: StatRange,
        source: TopTracksSource
    ) -> Int {
        slices[SliceKey(range: range, providerID: source.providerID)]?
            .playCounts?[track.key] ?? 0
    }

    func isInitiallyLoading(_ range: StatRange) -> Bool {
        isInitiallyLoading(range, source: .heartable)
    }

    func isInitiallyLoading(
        _ range: StatRange,
        source: TopTracksSource
    ) -> Bool {
        initialLoadingSlices.contains(
            SliceKey(range: range, providerID: source.providerID)
        )
    }

    func isRefreshing(_ range: StatRange) -> Bool {
        isRefreshing(range, source: .heartable)
    }

    func isRefreshing(
        _ range: StatRange,
        source: TopTracksSource
    ) -> Bool {
        refreshingSlices.contains(
            SliceKey(range: range, providerID: source.providerID)
        )
    }

    func lastUpdated(for range: StatRange) -> Date? {
        lastUpdated(for: range, source: .heartable)
    }

    func lastUpdated(
        for range: StatRange,
        source: TopTracksSource
    ) -> Date? {
        slices[SliceKey(range: range, providerID: source.providerID)]?.fetchedAt
    }

    /// Publish the account's disk snapshot without waiting for the provider
    /// connection probe. This is the fast first serve in stale-while-revalidate.
    func prepare() async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        await hydrate(ownerID: ownerID)
    }

    /// Hydrate once for the current account, then revalidate the account's
    /// observed play history. `providers` remains in the signature for existing
    /// callers, but connected catalogs do not decide what counts as a listen.
    func load(
        range: StatRange,
        providers: [MusicProvider],
        force: Bool = false
    ) async {
        await load(
            range: range,
            source: .heartable,
            providers: providers,
            force: force
        )
    }

    func load(
        range: StatRange,
        source: TopTracksSource,
        providers: [MusicProvider],
        force: Bool = false
    ) async {
        guard source.providesTopTracks else { return }
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        await hydrate(ownerID: ownerID)
        guard hydratedOwnerID == ownerID else { return }
        let requestLifecycleID = lifecycleID

        let key = SliceKey(range: range, providerID: source.providerID)
        let now = Date()
        if !force,
           let slice = slices[key],
           now.timeIntervalSince(slice.fetchedAt) < freshnessWindow {
            return
        }

        if tracks(for: range, source: source).isEmpty {
            initialLoadingSlices.insert(key)
        } else {
            refreshingSlices.insert(key)
        }

        switch source {
        case .heartable:
            await loadHeartable(
                range: range,
                key: key,
                providers: providers,
                ownerID: ownerID,
                lifecycle: requestLifecycleID,
                force: force,
                now: now
            )
        case .spotify:
            await loadSpotify(
                range: range,
                key: key,
                providers: providers,
                ownerID: ownerID,
                lifecycle: requestLifecycleID
            )
        case .apple:
            break
        }
    }

    private func loadHeartable(
        range: StatRange,
        key: SliceKey,
        providers: [MusicProvider],
        ownerID: UUID,
        lifecycle requestLifecycleID: UUID,
        force: Bool,
        now: Date
    ) async {
        let connectedProviderIDs = Set(providers.map(\.id))
        let history: [PlayEntryDTO]
        if !force,
           let historyFetchedAt,
           now.timeIntervalSince(historyFetchedAt) < freshnessWindow {
            history = historyEntries
        } else {
            let task = historyTask ?? Task {
                await BackendAPI.shared.fetchAllPlayHistory()
            }
            historyTask = task
            guard let fetched = await task.value else {
                historyTask = nil
                finishLoading(key)
                return
            }
            history = fetched
        }

        // Account reset can happen while the history request is suspended. Never
        // let an old account's late result clear or overwrite the new lifecycle.
        guard lifecycleID == requestLifecycleID,
              hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        historyTask = nil
        historyEntries = history
        historyFetchedAt = Date()

        let stats = await Task.detached(priority: .userInitiated) {
            Array(
                Self.aggregate(
                    entries: history,
                    range: range,
                    now: now,
                    preferredProviders: connectedProviderIDs
                )
                    .prefix(100)
            )
        }.value
        guard lifecycleID == requestLifecycleID,
              hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        slices[key] = ProviderSlice(
            range: range,
            providerID: .heartable,
            tracks: stats.map(\.track),
            playCounts: Dictionary(
                uniqueKeysWithValues: stats.map { ($0.track.key, $0.plays) }
            ),
            fetchedAt: Date()
        )
        publish(range)
        finishLoading(key)
        await persist(ownerID: ownerID)
    }

    private func loadSpotify(
        range: StatRange,
        key: SliceKey,
        providers: [MusicProvider],
        ownerID: UUID,
        lifecycle requestLifecycleID: UUID
    ) async {
        guard let spotify = providers.first(where: { $0.id == .spotify }) else {
            finishLoading(key)
            return
        }
        let tracks = await spotify.topTracks(range: range, limit: 100)
        guard lifecycleID == requestLifecycleID,
              hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        // Provider reads intentionally return [] for both an empty ranking and a
        // transport/auth failure. Preserve a last-good cache rather than turning
        // a transient Spotify failure into a false empty state.
        if tracks.isEmpty, !(slices[key]?.tracks.isEmpty ?? true) {
            finishLoading(key)
            return
        }

        slices[key] = ProviderSlice(
            range: range,
            providerID: .spotify,
            tracks: Self.uniqueTracks(tracks),
            playCounts: nil,
            fetchedAt: Date()
        )
        publish(range)
        finishLoading(key)
        await persist(ownerID: ownerID)
    }

    private func finishLoading(_ key: SliceKey) {
        initialLoadingSlices.remove(key)
        refreshingSlices.remove(key)
    }

    /// Clear account-owned in-memory state on sign-out/account switch. Disk files
    /// are removed by `AccountSessionStore`.
    func reset() {
        lifecycleID = UUID()
        hydrationTask?.cancel()
        historyTask?.cancel()
        hydrationTask = nil
        hydratingOwnerID = nil
        historyTask = nil
        historyEntries = []
        historyFetchedAt = nil
        slices = [:]
        tracksByRange = [:]
        playCountsByRange = [:]
        lastUpdatedByRange = [:]
        initialLoadingSlices = []
        refreshingSlices = []
        hydratedOwnerID = nil
    }

    /// Drop only Heartable-derived ranges after the play log changes. Persisting
    /// that removal prevents a deleted listen from flashing back while leaving
    /// independent Spotify rankings intact.
    func invalidateHistory() async {
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            reset()
            return
        }
        lifecycleID = UUID()
        historyTask?.cancel()
        historyTask = nil
        historyEntries = []
        historyFetchedAt = nil
        slices = slices.filter { $0.key.providerID != .heartable }
        tracksByRange = [:]
        playCountsByRange = [:]
        lastUpdatedByRange = [:]
        initialLoadingSlices = []
        refreshingSlices = []
        hydratedOwnerID = ownerID
        await persist(ownerID: ownerID)
    }

    private func hydrate(ownerID: UUID) async {
        guard hydratedOwnerID != ownerID else { return }

        let task: Task<DiskSnapshot?, Never>
        let hydrationLifecycleID: UUID
        if hydratingOwnerID == ownerID, let existing = hydrationTask {
            task = existing
            hydrationLifecycleID = lifecycleID
        } else {
            reset()
            hydratingOwnerID = ownerID
            hydrationLifecycleID = lifecycleID
            let url = Self.cacheURL(ownerID: ownerID)
            let io = cacheIO
            task = Task {
                guard let url else { return nil }
                return await io.load(from: url, ownerID: ownerID)
            }
            hydrationTask = task
        }

        let snapshot = await task.value
        guard lifecycleID == hydrationLifecycleID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        if hydratedOwnerID != ownerID {
            if let snapshot {
                for slice in snapshot.slices {
                    slices[SliceKey(range: slice.range, providerID: slice.providerID)] = slice
                }
            }
            hydratedOwnerID = ownerID
            publishAllRanges()
        }
        if hydratingOwnerID == ownerID {
            hydrationTask = nil
            hydratingOwnerID = nil
        }
    }

    private func publishAllRanges() {
        for range in StatRange.allCases { publish(range) }
    }

    private func publish(_ range: StatRange) {
        let heartable = slices[
            SliceKey(range: range, providerID: ProviderID.heartable)
        ]
        // Avoid needless Observation invalidations and SwiftUI list animations
        // when a background refresh returned the same canonical result.
        if tracksByRange[range] != (heartable?.tracks ?? []) {
            tracksByRange[range] = heartable?.tracks ?? []
        }
        playCountsByRange[range] = heartable?.playCounts ?? [:]
        lastUpdatedByRange[range] = heartable?.fetchedAt
    }

    private func persist(ownerID: UUID) async {
        guard let url = Self.cacheURL(ownerID: ownerID) else { return }
        let order = Dictionary(
            uniqueKeysWithValues: ProviderCatalog.all.enumerated().map { ($0.element.id, $0.offset) }
        )
        let orderedSlices = slices.values.sorted {
            if $0.range.rawValue != $1.range.rawValue {
                return $0.range.rawValue < $1.range.rawValue
            }
            return (order[$0.providerID] ?? .max) < (order[$1.providerID] ?? .max)
        }
        let snapshot = DiskSnapshot(
            version: DiskSnapshot.currentVersion,
            ownerID: ownerID,
            slices: orderedSlices
        )
        await cacheIO.save(snapshot, to: url)
    }

    private static func cacheURL(ownerID: UUID) -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
            .appendingPathComponent(
                AccountSessionStore.scopedFilename(
                    "top-tracks",
                    ext: "json",
                    ownerID: ownerID
                )
            )
    }

    /// Provider rankings occasionally repeat a stable id. Remove only exact
    /// duplicates from that source; never compare title/artist or another source.
    nonisolated static func uniqueTracks(_ tracks: [UnifiedTrack]) -> [UnifiedTrack] {
        var seen = Set<String>()
        return tracks.filter { track in
            seen.insert(track.key).inserted
        }
    }

    /// Build one Heartable row per normalized song and rank it by observed plays,
    /// then recency. Provider copies of the same song roll into the Heartable
    /// total, while provider rankings remain isolated in their own source slice.
    nonisolated static func aggregate(
        entries: [PlayEntryDTO],
        range: StatRange,
        now: Date,
        preferredProviders: Set<ProviderID> = []
    ) -> [TrackStat] {
        struct Accumulator {
            var track: UnifiedTrack
            var plays: Int
            var lastPlayedAt: Date
        }

        let cutoff: Date? = switch range {
        case .shortTerm: now.addingTimeInterval(-28 * 86_400)
        case .mediumTerm: now.addingTimeInterval(-180 * 86_400)
        case .longTerm: nil
        }
        let fractionalDate = ISO8601DateFormatter()
        fractionalDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardDate = ISO8601DateFormatter()

        var grouped: [String: Accumulator] = [:]
        for entry in entries {
            guard let title = entry.trackName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            let artist = entry.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let playedAt = entry.playedAt.flatMap {
                fractionalDate.date(from: $0) ?? standardDate.date(from: $0)
            } ?? .distantPast
            if let cutoff, playedAt < cutoff { continue }

            let track = track(from: entry, title: title, artist: artist)
            let identity = UnifiedTrackIdentity.make(title: title, artist: artist)
            if var existing = grouped[identity.key] {
                existing.plays += 1
                existing.lastPlayedAt = max(existing.lastPlayedAt, playedAt)
                if prefers(track, over: existing.track, preferredProviders: preferredProviders) {
                    existing.track = track
                }
                grouped[identity.key] = existing
            } else {
                grouped[identity.key] = Accumulator(
                    track: track,
                    plays: 1,
                    lastPlayedAt: playedAt
                )
            }
        }

        return grouped
            .map { TrackStat(track: $0.value.track, plays: $0.value.plays, lastPlayedAt: $0.value.lastPlayedAt) }
            .sorted {
                if $0.plays != $1.plays { return $0.plays > $1.plays }
                if $0.lastPlayedAt != $1.lastPlayedAt { return $0.lastPlayedAt > $1.lastPlayedAt }
                return $0.track.name.localizedCaseInsensitiveCompare($1.track.name) == .orderedAscending
            }
    }

    private nonisolated static func track(
        from entry: PlayEntryDTO,
        title: String,
        artist: String
    ) -> UnifiedTrack {
        let uri = entry.trackUri ?? "heartable:track:\(entry.id.uuidString)"
        let components = uri.split(separator: ":")
        let provider = components.first
            .flatMap { ProviderID(rawValue: String($0)) } ?? .heartable
        let providerTrackID = components.last.map(String.init) ?? entry.id.uuidString
        let artists = artist.isEmpty
            ? []
            : [UnifiedArtist(
                id: UnifiedTrackIdentity.normalizeArtist(artist),
                name: artist
            )]
        return UnifiedTrack(
            key: trackKey(provider, providerTrackID),
            providerID: provider,
            providerTrackID: providerTrackID,
            uri: uri,
            name: title,
            artists: artists,
            album: nil,
            albumArt: entry.albumArt.flatMap(URL.init(string:)),
            durationMs: entry.durationMs ?? 0
        )
    }

    private nonisolated static func prefers(
        _ candidate: UnifiedTrack,
        over existing: UnifiedTrack,
        preferredProviders: Set<ProviderID>
    ) -> Bool {
        let candidatePreferred = preferredProviders.contains(candidate.providerID)
        let existingPreferred = preferredProviders.contains(existing.providerID)
        if candidatePreferred != existingPreferred { return candidatePreferred }
        let candidateTier = ProviderPlayback.tier(for: candidate.providerID)
        let existingTier = ProviderPlayback.tier(for: existing.providerID)
        if candidateTier != existingTier { return candidateTier > existingTier }
        if (candidate.albumArt != nil) != (existing.albumArt != nil) {
            return candidate.albumArt != nil
        }
        return candidate.durationMs > existing.durationMs
    }
}
