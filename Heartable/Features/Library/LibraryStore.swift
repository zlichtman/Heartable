import Foundation
import Observation
import os

private let libraryLog = Logger(subsystem: "com.zlichtman.heartable", category: "library")

/// Aggregates the master library across all connected providers: top, liked,
/// playlists, artists, and unified search. Ported from the RN LibraryScreen logic.
@MainActor
@Observable
final class LibraryStore {
    struct ArtistAgg: Identifiable, Sendable, Hashable {
        let name: String
        var count: Int
        var providers: Set<ProviderID>
        var artURL: URL?
        /// First Spotify artist id seen for this name — lets us fetch the real
        /// artist photo (track artist objects carry no image). nil for non-Spotify.
        var spotifyArtistID: String?
        var id: String { name.lowercased() }
    }

    struct SearchResults: Sendable {
        var tracks: [UnifiedTrack] = []
        var playlists: [UnifiedPlaylist] = []
        var artists: [ArtistAgg] = []
        var people: [FoundProfileDTO] = []
        var isEmpty: Bool { tracks.isEmpty && playlists.isEmpty && artists.isEmpty && people.isEmpty }
    }

    /// One track found somewhere in the library, with the playlist it came from
    /// (nil = liked or top, i.e. not from a specific playlist).
    struct LibraryEntry: Sendable {
        let track: UnifiedTrack
        let playlist: UnifiedPlaylist?
    }

    private(set) var topTracks: [UnifiedTrack] = []
    private(set) var likedTracks: [UnifiedTrack] = []
    private(set) var playlists: [UnifiedPlaylist] = []
    private(set) var artists: [ArtistAgg] = []
    private(set) var loading = false
    private(set) var refreshing = false
    /// Why the last refresh could not reach a service, in user words. nil when
    /// every requested provider answered. Cached content stays on screen.
    private(set) var providerNotice: String?

    /// Every track found anywhere in the library, with playlist attribution.
    /// Rebuilt from the persistent playlist-content repository so the Artists tab
    /// is complete without re-downloading every playlist each time it opens.
    private(set) var libraryTracks: [LibraryEntry] = []
    /// True while the playlist-content index is reconciling.
    private(set) var indexingArtists = false
    /// Whether every current playlist has a resolved cache entry.
    private(set) var didBuildArtistIndex = false

    /// On-disk snapshot so the library shows instantly on launch and survives a
    /// transient provider/token failure (which is why it used to vanish until a
    /// disconnect/reconnect). Artists are recomputed from cached tracks.
    private struct CacheSnapshot: Codable, Sendable {
        var top: [UnifiedTrack]
        var liked: [UnifiedTrack]
        var playlists: [UnifiedPlaylist]
        var savedAt: Date
        /// Optional so snapshots written by earlier builds continue to decode.
        var providerIDs: Set<ProviderID>?
    }

    /// JSON encoding/decoding and filesystem access can be sizeable for a large
    /// liked library. Keeping it behind an actor guarantees none of it runs on
    /// the UI's MainActor.
    private actor CacheIO {
        func load(from url: URL?) -> CacheSnapshot? {
            guard let url, let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(CacheSnapshot.self, from: data)
        }

        func save(_ snapshot: CacheSnapshot, to url: URL?) {
            guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func cacheURL(ownerID: UUID) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(
                AccountSessionStore.scopedFilename(
                    "heartable-library-cache",
                    ext: "json",
                    ownerID: ownerID
                )
            )
    }

    private var didHydrate = false
    private var hydratedOwnerID: UUID?
    private var lifecycleID = UUID()
    private var cachedAt: Date?
    private var loadedProviders: Set<ProviderID>?
    private let cacheIO = CacheIO()
    /// Skip a network refresh if the cache is younger than this (rate-limit guard).
    private let freshnessWindow: TimeInterval = 300

    /// Hydrate independently of a provider refresh so views can render cached
    /// content while the app is still resolving which services are connected.
    func hydrate() async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        guard !didHydrate || hydratedOwnerID != ownerID else { return }
        didHydrate = true
        hydratedOwnerID = ownerID
        let requestID = lifecycleID
        async let cachedImageLookup = ArtworkDiskCache.shared.artistImageURLs()
        guard let cache = await cacheIO.load(from: Self.cacheURL(ownerID: ownerID)),
              lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        // Publish the useful Home payload before doing any artist aggregation.
        // This is the important latency boundary: playlist tiles and liked songs
        // must never wait for the derived Artists view.
        topTracks = cache.top
        likedTracks = cache.liked
        playlists = cache.playlists
        cachedAt = cache.savedAt
        loadedProviders = cache.providerIDs
        warmVisibleArtwork()

        let images = await cachedImageLookup
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        artistImageCache = images
        let cachedImages = artistImageCache
        let cachedArtists = await Task.detached(priority: .userInitiated) {
            Self.aggregateArtists(cache.top + cache.liked, cachedImages: cachedImages)
        }.value
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        artists = cachedArtists
    }

    /// Refresh using the already-probed provider list from `ProvidersStore`.
    /// This avoids probing every adapter a second time merely to start a load.
    func loadAll(providers: [MusicProvider], force: Bool = false) async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        let requestID = lifecycleID
        await hydrate()
        guard lifecycleID == requestID,
              hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        let providerIDs = Set(providers.map(\.id))
        if !force,
           providerNotice == nil,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < freshnessWindow,
           loadedProviders == providerIDs,
           !playlists.isEmpty {
            return
        }
        guard !refreshing else { return }
        refreshing = true
        loading = playlists.isEmpty && topTracks.isEmpty && likedTracks.isEmpty
        defer {
            loading = false
            refreshing = false
        }

        async let top = ProviderCacheMerge.gather(providers) { await $0.readTopTracks(range: .mediumTerm, limit: 50) }
        // High cap so the master Liked list pulls a full library (Spotify pages
        // 50/request until exhausted), not just the first page.
        async let liked = ProviderCacheMerge.gather(providers) { await $0.readLikedTracks(limit: 10000) }
        async let pls = ProviderCacheMerge.gather(providers) { await $0.readPlaylists() }
        async let tapes = BackendAPI.shared.fetchMixtapesIfAvailable()

        // Publish the playlist catalog the moment it lands. On a fresh account
        // the full liked-songs pull can take minutes (Spotify pages 50 at a
        // time and may answer 429), and Home must not sit on a spinner for it.
        let mixtapeList = await tapes
        let playlistReads = await pls
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        // A failed backend read is not an empty mixtape shelf.
        let mixtapes = mixtapeList.map { ($0.mine + $0.shared).map(Self.mapMixtape) }
            ?? playlists.filter(\.isMixtape)
        let orderedIDs = providers.map(\.id)
        playlists = dedupePlaylists(mixtapes + preservingPlaylistArtwork(ProviderCacheMerge.merge(
            cached: playlists.filter { !$0.isMixtape }, providers: orderedIDs,
            reads: playlistReads, providerID: { $0.providerID }
        ), cached: playlists))
        // The playlist pass has resolved: "loaded, empty" is a state, not a spinner.
        loading = false
        for id in orderedIDs {
            let outcome = playlistReads[id]?.items.map { "success(\($0.count))" } ?? "unavailable"
            libraryLog.notice("playlists \(id.rawValue, privacy: .public): \(outcome, privacy: .public)")
        }
        providerNotice = await Self.notice(for: orderedIDs, reads: playlistReads)
        // A kill during the minutes-long liked pull must not lose the playlist
        // catalog; the empty provider set forces a full pass on the next launch.
        await saveCache(providerIDs: [], ownerID: ownerID)
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        let topReads = await top
        let likedReads = await liked
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        for id in orderedIDs {
            let liked = likedReads[id]?.items.map { "success(\($0.count))" } ?? "unavailable"
            let top = topReads[id]?.items.map { "success(\($0.count))" } ?? "unavailable"
            libraryLog.notice("liked \(id.rawValue, privacy: .public): \(liked, privacy: .public); top: \(top, privacy: .public)")
        }

        topTracks = preservingTrackArtwork(dedupeTracks(ProviderCacheMerge.merge(
            cached: topTracks, providers: orderedIDs, reads: topReads, providerID: { $0.providerID }
        )), cached: topTracks)
        likedTracks = preservingTrackArtwork(dedupeTracks(ProviderCacheMerge.merge(
            cached: likedTracks, providers: orderedIDs, reads: likedReads, providerID: { $0.providerID }
        )), cached: likedTracks)

        let refreshedTracks = topTracks + likedTracks
        let cachedImages = artistImageCache
        artists = await Task.detached(priority: .userInitiated) {
            Self.aggregateArtists(refreshedTracks, cachedImages: cachedImages)
        }.value
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        // When every requested service failed, nothing was verified: keep the
        // derived index, do not stamp freshness, and let the next pass retry.
        let anySuccess = orderedIDs.isEmpty || orderedIDs.contains { id in
            playlistReads[id]?.items != nil || likedReads[id]?.items != nil || topReads[id]?.items != nil
        }
        guard anySuccess else {
            libraryLog.error("no provider answered; keeping cached library and freshness untouched")
            return
        }
        // The playlist catalog may carry new content revisions or track counts.
        // The shared repository reconciles those immediately after this metadata
        // pass and then rebuilds the artist projection.
        didBuildArtistIndex = false
        libraryTracks = []
        cachedAt = Date()
        loadedProviders = providerIDs
        await saveCache(providerIDs: providerIDs, ownerID: ownerID)
        warmVisibleArtwork()
    }

    /// Preload the artwork users are most likely to see next. Cached library
    /// metadata still paints immediately; this work happens independently and
    /// gives Apple Music's colder image CDN a head start after launch/cache clear.
    private func warmVisibleArtwork() {
        let tracks = topTracks + likedTracks
        let appleURLs = tracks.lazy
            .filter { $0.providerID == .apple }
            .compactMap(\.albumArt)
            .prefix(120)
        let playlistURLs = playlists.lazy
            .filter { $0.providerID == .apple }
            .compactMap(\.image)
            .prefix(40)
        let otherURLs = tracks.lazy
            .filter { $0.providerID != .apple }
            .compactMap(\.albumArt)
            .prefix(40)
        let urls = Array(appleURLs) + Array(playlistURLs) + Array(otherURLs)
        Task { await ArtworkImageCache.shared.prefetch(urls) }
    }

    private func preservingTrackArtwork(
        _ fresh: [UnifiedTrack],
        cached: [UnifiedTrack]
    ) -> [UnifiedTrack] {
        let cachedByKey = Dictionary(
            cached.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return fresh.map { $0.preservingArtwork(from: cachedByKey[$0.key]) }
    }

    private func preservingPlaylistArtwork(
        _ fresh: [UnifiedPlaylist],
        cached: [UnifiedPlaylist]
    ) -> [UnifiedPlaylist] {
        let cachedByKey = Dictionary(
            cached.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return fresh.map { $0.preservingArtwork(from: cachedByKey[$0.key]) }
    }

    /// Rebuild the artist projection immediately from already-persisted playlist
    /// content. Called during hydration so cached artist songs appear before the
    /// network change check completes.
    func restoreArtistIndex(from repository: PlaylistTracksRepository) async {
        await rebuildArtistIndex(from: repository)
    }

    /// Ensures the playlist cache is authoritative, then rebuilds the library-wide
    /// artist index from liked + top + every playlist. The first call fetches all
    /// playlists; later calls fetch only changed/stale entries unless `force`.
    func loadArtistIndex(
        using repository: PlaylistTracksRepository,
        force: Bool = false
    ) async {
        let requestID = lifecycleID
        if indexingArtists { return }
        indexingArtists = true
        defer { indexingArtists = false }

        await repository.synchronize(playlists, force: force)
        guard lifecycleID == requestID else { return }
        await rebuildArtistIndex(from: repository)
        guard lifecycleID == requestID else { return }
        await enrichArtistImages()
    }

    /// Forget all account-owned state and invalidate work that began for a prior
    /// Heartable account. The instance itself remains stable for SwiftUI.
    func reset() {
        lifecycleID = UUID()
        topTracks = []
        likedTracks = []
        playlists = []
        artists = []
        libraryTracks = []
        loading = false
        refreshing = false
        providerNotice = nil
        indexingArtists = false
        didBuildArtistIndex = false
        didHydrate = false
        hydratedOwnerID = nil
        cachedAt = nil
        loadedProviders = nil
        artistImageCache = [:]
    }

    private func rebuildArtistIndex(from repository: PlaylistTracksRepository) async {
        let requestID = lifecycleID
        let ownerID = AccountSessionStore.currentOwnerID
        let baseTracks = likedTracks + topTracks
        let cachedContents = repository.cachedContents(for: playlists)
        let cachedImages = artistImageCache
        let projection = await Task.detached(priority: .userInitiated) {
            Self.makeArtistProjection(
                baseTracks: baseTracks,
                playlistContents: cachedContents,
                cachedImages: cachedImages
            )
        }.value
        guard lifecycleID == requestID, AccountSessionStore.currentOwnerID == ownerID else { return }
        libraryTracks = projection.entries
        artists = projection.artists
        didBuildArtistIndex = repository.hasResolvedAll(playlists)
    }

    /// Drop deleted personal mixtapes without evicting connected-service caches.
    func removeOwnedMixtapes(using repository: PlaylistTracksRepository) async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        lifecycleID = UUID()
        let removed = Set(playlists.filter {
            $0.providerID == .heartable && $0.owner == "Heartable Mixtape"
        }.map(\.key))
        playlists.removeAll { removed.contains($0.key) }
        await repository.remove(keys: removed)
        guard AccountSessionStore.currentOwnerID == ownerID else { return }
        await rebuildArtistIndex(from: repository)
        await saveCache(providerIDs: loadedProviders ?? [], ownerID: ownerID)
    }

    /// One sentence for the Library when a requested service could not answer.
    /// Spotify's own cooldown is named with its end time so the user knows the
    /// library is intact and when it refreshes; anything else names the service.
    private static func notice(
        for providerIDs: [ProviderID],
        reads: [ProviderID: ProviderRead<UnifiedPlaylist>]
    ) async -> String? {
        let failed = providerIDs.filter { reads[$0]?.items == nil }
        guard !failed.isEmpty else { return nil }
        if failed.contains(.spotify), let resume = await SpotifyReadBackoff.shared.resumeDate() {
            let time = resume.formatted(date: .omitted, time: .shortened)
            let day = Calendar.current.isDateInToday(resume) ? "" : " " + resume.formatted(date: .abbreviated, time: .omitted)
            return "Spotify is limiting requests. Heartable will refresh at \(time)\(day). Your saved library stays available."
        }
        let names = failed.map { ProviderCatalog.entry($0)?.label ?? $0.rawValue }
        let list = ListFormatter.localizedString(byJoining: names)
        if failed.contains(.spotify), let detail = await SpotifyReadBackoff.shared.lastFailure {
            return "Spotify answered \(detail). Showing your saved library."
        }
        return "Couldn’t reach \(list). Showing your saved library."
    }

    private func saveCache(providerIDs: Set<ProviderID>, ownerID: UUID) async {
        guard hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        let snap = CacheSnapshot(
            top: topTracks,
            liked: likedTracks,
            playlists: playlists,
            savedAt: cachedAt ?? Date(),
            providerIDs: providerIDs
        )
        await cacheIO.save(snap, to: Self.cacheURL(ownerID: ownerID))
    }

    /// ISO-8601 timestamps from Postgres, with and without fractional seconds.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso = ISO8601DateFormatter()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    private static func mapMixtape(_ m: MixtapeDTO) -> UnifiedPlaylist {
        UnifiedPlaylist(
            key: "heartable:\(m.id.uuidString)",
            providerID: .heartable,
            playlistID: m.id.uuidString,
            name: m.title?.isEmpty == false ? m.title! : "Untitled mixtape",
            description: m.description,
            image: m.coverUrl.flatMap(URL.init(string:)),
            trackCount: 0,
            owner: m.mine ? "Heartable Mixtape" : "Shared mixtape",
            createdAt: parseDate(m.createdAt)
        )
    }

    /// All library entries (track + playlist attribution) for a given artist,
    /// matched case-insensitively by name. Powers ArtistDetailView. Empty until
    /// `loadArtistIndex()` has run.
    func entries(forArtist name: String) -> [LibraryEntry] {
        let key = name.lowercased()
        return libraryTracks.filter { entry in
            entry.track.artists.contains { $0.name.lowercased() == key }
        }
    }

    /// Artists have only two meaningful orders: name and the number of songs found
    /// across the user's library. Playlist-specific concepts such as creator,
    /// recency, and manual order never leak into this surface.
    func sortedArtists(_ mode: LibrarySortStore.ArtistSortMode) -> [ArtistAgg] {
        switch mode {
        case .alphabetical:
            return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .songCount:
            return artists.sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    func search(_ query: String) async -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SearchResults() }
        let providers = await ProviderRegistry.connected()

        async let foundTracks = gather(providers) { await $0.search(q) }
        async let people = (try? await BackendAPI.shared.findProfiles(query: q)) ?? []

        let tracks = dedupeTracks(await foundTracks)
        let matchingPlaylists = playlists.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let cachedImages = artistImageCache
        let artistMatches = await Task.detached(priority: .userInitiated) {
            Self.aggregateArtists(tracks, cachedImages: cachedImages)
                .filter { $0.name.localizedCaseInsensitiveContains(q) }
        }.value
        return SearchResults(tracks: tracks, playlists: matchingPlaylists,
                             artists: artistMatches, people: await people)
    }

    // MARK: Helpers

    private func gather(_ providers: [MusicProvider],
                        _ op: @escaping @Sendable (MusicProvider) async -> [UnifiedTrack]) async -> [UnifiedTrack] {
        await withTaskGroup(of: [UnifiedTrack].self) { group in
            for p in providers { group.addTask { await op(p) } }
            var all: [UnifiedTrack] = []
            for await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    private func dedupeTracks(_ tracks: [UnifiedTrack]) -> [UnifiedTrack] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.key).inserted }
    }

    /// A provider can hand back the same playlist twice across pages. Identity
    /// is the key, and duplicate identities must never reach a ForEach or a
    /// keyed dictionary.
    private func dedupePlaylists(_ playlists: [UnifiedPlaylist]) -> [UnifiedPlaylist] {
        var seen = Set<String>()
        return playlists.filter { seen.insert($0.key).inserted }
    }

    private struct ArtistProjection: Sendable {
        let entries: [LibraryEntry]
        let artists: [ArtistAgg]
    }

    private nonisolated static func makeArtistProjection(
        baseTracks: [UnifiedTrack],
        playlistContents: [(playlist: UnifiedPlaylist, tracks: [UnifiedTrack])],
        cachedImages: [String: URL]
    ) -> ArtistProjection {
        var entries = baseTracks.map { LibraryEntry(track: $0, playlist: nil) }
        for content in playlistContents {
            entries.append(contentsOf: content.tracks.map {
                LibraryEntry(track: $0, playlist: content.playlist)
            })
        }
        return ArtistProjection(
            entries: entries,
            artists: aggregateArtists(entries.map(\.track), cachedImages: cachedImages)
        )
    }

    private nonisolated static func aggregateArtists(
        _ tracks: [UnifiedTrack],
        cachedImages: [String: URL]
    ) -> [ArtistAgg] {
        var map: [String: ArtistAgg] = [:]
        var songsByArtist: [String: Set<String>] = [:]
        let stableTracks = tracks.sorted { lhs, rhs in
            if lhs.providerID != rhs.providerID {
                return ArtworkSourcePreference.precedes(
                    lhs.providerID,
                    rhs.providerID
                )
            }
            let leftIdentity = UnifiedTrackIdentity.make(
                title: lhs.name,
                artist: lhs.artists.first?.name ?? ""
            ).key
            let rightIdentity = UnifiedTrackIdentity.make(
                title: rhs.name,
                artist: rhs.artists.first?.name ?? ""
            ).key
            return leftIdentity < rightIdentity
        }
        for t in stableTracks {
            for a in t.artists where !a.name.isEmpty {
                let key = a.name.lowercased()
                let spotifyID = t.providerID == .spotify && !a.id.isEmpty ? a.id : nil
                let songIdentity = UnifiedTrackIdentity.make(
                    title: t.name,
                    artist: a.name
                ).key
                let isNewSong = songsByArtist[key, default: []].insert(songIdentity).inserted
                if var agg = map[key] {
                    if isNewSong { agg.count += 1 }
                    agg.providers.insert(t.providerID)
                    if agg.artURL == nil { agg.artURL = t.albumArt }
                    if agg.spotifyArtistID == nil { agg.spotifyArtistID = spotifyID }
                    map[key] = agg
                } else {
                    map[key] = ArtistAgg(name: a.name, count: 1,
                                         providers: [t.providerID], artURL: t.albumArt,
                                         spotifyArtistID: spotifyID)
                }
            }
        }
        // Apply any real artist photos already fetched this session (album art is
        // the fallback until/unless a photo exists).
        return map.values
            .map { artist in
                guard let spotifyID = artist.spotifyArtistID,
                      let image = cachedImages[spotifyID] else { return artist }
                var enriched = artist
                enriched.artURL = image
                return enriched
            }
            .sorted { $0.count > $1.count }
    }

    // MARK: Artist images

    /// Real artist photos keyed by Spotify artist id, fetched once and reused.
    private var artistImageCache: [String: URL] = [:]

    private func applyCachedImage(_ agg: ArtistAgg) -> ArtistAgg {
        guard let sid = agg.spotifyArtistID, let url = artistImageCache[sid] else { return agg }
        var a = agg
        a.artURL = url
        return a
    }

    /// Fetch real Spotify artist photos for any artists we don't have one for yet,
    /// then swap them into `artists` (album art stays the fallback). Network only
    /// for ids not already cached; safe to call repeatedly. No-op without Spotify.
    func enrichArtistImages() async {
        let needed = artists
            .compactMap(\.spotifyArtistID)
            .filter { artistImageCache[$0] == nil }
        guard !needed.isEmpty, let token = await SpotifyAuth.getValidAccessToken() else { return }
        let artworkCacheGeneration = await ArtworkDiskCache.shared.currentGeneration()
        let fetched = await SpotifyAPI.artistImages(token: token, ids: needed)
        guard !fetched.isEmpty else { return }
        for (k, v) in fetched { artistImageCache[k] = v }
        await ArtworkDiskCache.shared.storeArtistImageURLs(
            artistImageCache,
            generation: artworkCacheGeneration
        )
        artists = artists.map { applyCachedImage($0) }
    }
}
