import Foundation
import Observation

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

    func loadAll(force: Bool = false) async {
        let connected = await ProviderRegistry.connected()
        await loadAll(providers: connected, force: force)
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

        async let top = gather(providers) { await $0.topTracks(range: .mediumTerm, limit: 50) }
        // High cap so the master Liked list pulls a full library (Spotify pages
        // 50/request until exhausted), not just the first page.
        async let liked = gather(providers) { await $0.likedTracks(limit: 10000) }
        async let pls = gatherPlaylists(providers)
        async let tapes = BackendAPI.shared.listMixtapes()

        let freshTop = dedupeTracks(await top)
        let freshLiked = dedupeTracks(await liked)
        let mixtapeList = await tapes
        let mixtapes = (mixtapeList.mine + mixtapeList.shared).map(Self.mapMixtape)
        let freshProviderPlaylists = await pls
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        // Non-empty wins: never overwrite good cached data with an empty result
        // (an empty fetch almost always means a transient token/network failure,
        // not that the user's library is actually empty).
        if providers.isEmpty {
            // At this point the caller has completed a real connection probe, so
            // empty means disconnected rather than "not checked yet".
            topTracks = []
            likedTracks = []
        } else {
            // A disconnected provider must disappear even when every currently
            // connected provider legitimately returns an empty top/liked set.
            topTracks = topTracks.filter { providerIDs.contains($0.providerID) }
            likedTracks = likedTracks.filter { providerIDs.contains($0.providerID) }
            if !freshTop.isEmpty {
                topTracks = preservingTrackArtwork(freshTop, cached: topTracks)
            }
            if !freshLiked.isEmpty {
                likedTracks = preservingTrackArtwork(freshLiked, cached: likedTracks)
            }
        }
        if !freshProviderPlaylists.isEmpty || providers.isEmpty {
            playlists = mixtapes + preservingPlaylistArtwork(
                freshProviderPlaylists,
                cached: playlists
            )
        } else {
            // Provider playlists failed to load — keep the cached ones, refresh tapes.
            playlists = mixtapes + playlists.filter {
                !$0.isMixtape && providerIDs.contains($0.providerID)
            }
        }

        let refreshedTracks = topTracks + likedTracks
        let cachedImages = artistImageCache
        artists = await Task.detached(priority: .userInitiated) {
            Self.aggregateArtists(refreshedTracks, cachedImages: cachedImages)
        }.value
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
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
        indexingArtists = false
        didBuildArtistIndex = false
        didHydrate = false
        hydratedOwnerID = nil
        cachedAt = nil
        loadedProviders = nil
        artistImageCache = [:]
    }

    private func rebuildArtistIndex(from repository: PlaylistTracksRepository) async {
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

        libraryTracks = projection.entries
        artists = projection.artists
        didBuildArtistIndex = repository.hasResolvedAll(playlists)
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

    private func gatherPlaylists(_ providers: [MusicProvider]) async -> [UnifiedPlaylist] {
        await withTaskGroup(of: [UnifiedPlaylist].self) { group in
            for p in providers { group.addTask { await p.playlists() } }
            var all: [UnifiedPlaylist] = []
            for await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    private func dedupeTracks(_ tracks: [UnifiedTrack]) -> [UnifiedTrack] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.key).inserted }
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
