import Foundation
import Observation

/// Owns the unified master library and the single federated search.
///
/// - LIBRARY: loads each connected provider's top + liked (and, on demand, every
///   playlist), merges them into a de-duplicated `[MasterTrack]` / `[MasterArtist]`
///   keyed by cross-service identity, records provenance (which services serve
///   each item + their native ids), persists a `MasterLibrarySnapshot` so it shows
///   instantly on launch, and reconciles connect/disconnect + transient failures.
/// - SEARCH: `setSearch(_:localPlaylists:)` runs one debounced, cancellable query
///   across all connected providers concurrently, isolates per-provider failure
///   and slowness (soft timeout), merges + de-dupes + ranks, and applies the
///   result ATOMICALLY (one assignment) so the list never flickers or reflows as
///   individual services return.
@MainActor
@Observable
final class MasterLibraryStore {

    // MARK: - Library state

    private(set) var tracks: [MasterTrack] = []
    private(set) var artists: [MasterArtist] = []
    private(set) var loading = false
    private(set) var lastLoadedAt: Date?

    // MARK: - Search state

    struct SearchResults: Sendable {
        var tracks: [MasterTrack] = []
        var artists: [MasterArtist] = []
        var playlists: [UnifiedPlaylist] = []
        var people: [FoundProfileDTO] = []
        var isEmpty: Bool {
            tracks.isEmpty && artists.isEmpty && playlists.isEmpty && people.isEmpty
        }
    }

    private(set) var searchTerm = ""
    private(set) var searching = false
    private(set) var searchResults = SearchResults()
    /// True after a search completed with zero connected providers (drives the
    /// "connect a service" hint without swapping the whole view).
    private(set) var searchedWithNoProviders = false

    // MARK: - Internals

    private var didHydrate = false
    private var hydratedOwnerID: UUID?
    private var lifecycleID = UUID()
    private var didDeepIndex = false
    private var loadedProviders: Set<ProviderID> = []
    private var searchTask: Task<Void, Never>?

    /// Skip a background refresh while the snapshot is younger than this.
    private let staleWindow: TimeInterval = 900          // 15 minutes
    /// Debounce window before a new query hits the network.
    private let debounce: Duration = .milliseconds(300)
    /// Per-provider soft cap so one slow service can't stall the whole search.
    private let providerSearchTimeout: TimeInterval = 6

    // MARK: - Hydrate

    /// Load the persisted snapshot once per session (decoded off the main actor).
    func hydrate() async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        guard !didHydrate || hydratedOwnerID != ownerID else { return }
        didHydrate = true
        hydratedOwnerID = ownerID
        let requestID = lifecycleID
        let snapshot = await Task.detached(priority: .userInitiated) {
            MasterLibrarySnapshot.load(ownerID: ownerID)
        }.value
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID,
              let snapshot,
              tracks.isEmpty else { return }
        let hydratedArtists = if snapshot.artists.isEmpty {
            await Task.detached(priority: .userInitiated) {
                MasterArtist.aggregate(snapshot.tracks)
            }.value
        } else {
            snapshot.artists
        }
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        tracks = snapshot.tracks
        artists = hydratedArtists
        lastLoadedAt = snapshot.savedAt
    }

    // MARK: - Load / refresh

    /// Refresh the master library from every connected provider. Hydrates first so
    /// the UI shows cached data instantly. Skips the network when the snapshot is
    /// fresh, the connected set is unchanged, and we already have data (unless
    /// `force`, e.g. pull-to-refresh or a connect/disconnect).
    func load(force: Bool = false) async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        let requestID = lifecycleID
        await hydrate()
        guard lifecycleID == requestID,
              hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        let providers = await ProviderRegistry.connected()
        let liveIDs = Set(providers.map(\.id))

        if !force,
           let at = lastLoadedAt,
           Date().timeIntervalSince(at) < staleWindow,
           liveIDs == loadedProviders,
           !tracks.isEmpty {
            return
        }

        loading = tracks.isEmpty
        // A changed provider set invalidates the deep (playlist) index.
        if liveIDs != loadedProviders { didDeepIndex = false }

        async let topFetch = Self.gather(providers) { await $0.topTracks(range: .mediumTerm, limit: 50) }
        async let likedFetch = Self.gather(providers) { await $0.likedTracks(limit: 10_000) }
        let fetched = await topFetch + likedFetch
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }

        loading = false
        let cachedTracks = tracks
        let projection = await Task.detached(priority: .userInitiated) {
            Self.reconcile(
                fetched: fetched,
                attempted: liveIDs,
                cachedTracks: cachedTracks
            )
        }.value
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        tracks = projection.tracks
        artists = projection.artists
        loadedProviders = liveIDs
        lastLoadedAt = Date()
        persist()
    }

    /// Consume the source tracks already fetched by `LibraryStore`. Library browse
    /// and the master/search index used to independently fan out top + liked calls
    /// to every provider; this makes the browse pipeline authoritative and keeps
    /// the master projection as a cheap in-memory reconciliation.
    func adopt(_ sourceTracks: [UnifiedTrack], providerIDs: Set<ProviderID>) async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        let requestID = lifecycleID
        await hydrate()
        guard lifecycleID == requestID,
              hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        if providerIDs != loadedProviders { didDeepIndex = false }
        let cachedTracks = tracks
        let projection = await Task.detached(priority: .userInitiated) {
            Self.reconcile(
                fetched: sourceTracks,
                attempted: providerIDs,
                cachedTracks: cachedTracks
            )
        }.value
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        tracks = projection.tracks
        artists = projection.artists
        loadedProviders = providerIDs
        lastLoadedAt = Date()
        persist()
    }

    /// Fold every provider playlist's tracks into the master set (bounded
    /// concurrency). Additive and session-idempotent: it only widens provenance,
    /// never drops sources, and re-runs after a provider set change. Mixtapes are
    /// skipped (their tracks already reference underlying provider tracks).
    func deepIndex(playlists: [UnifiedPlaylist]) async {
        guard let ownerID = AccountSessionStore.currentOwnerID,
              hydratedOwnerID == ownerID else { return }
        let requestID = lifecycleID
        guard !didDeepIndex else { return }
        let providerPlaylists = playlists.filter { !$0.isMixtape }
        guard !providerPlaylists.isEmpty else { return }
        didDeepIndex = true

        let fetched = await Self.gatherPlaylistTracks(providerPlaylists, maxConcurrent: 6)
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        let cachedTracks = tracks
        let projection = await Task.detached(priority: .userInitiated) {
            Self.deepProjection(cachedTracks: cachedTracks, fetched: fetched)
        }.value
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        tracks = projection.tracks
        artists = projection.artists
        persist()
    }

    // MARK: - Reconcile

    /// Rebuild the master set from a fresh fetch, preserving provenance safely:
    ///  - A provider that RETURNED data is authoritative: only its fresh sources
    ///    survive (a song it no longer serves is dropped from it).
    ///  - A provider that was CONNECTED but returned nothing is treated as a
    ///    transient failure: its cached sources are kept (non-empty-wins).
    ///  - A provider that is NO LONGER CONNECTED is dropped entirely.
    ///  - A master track left with no sources disappears.
    private struct LibraryProjection: Sendable {
        let tracks: [MasterTrack]
        let artists: [MasterArtist]
    }

    private nonisolated static func reconcile(
        fetched: [UnifiedTrack],
        attempted: Set<ProviderID>,
        cachedTracks: [MasterTrack]
    ) -> LibraryProjection {
        let returned = Set(fetched.map(\.providerID))
        let cachedByKey = Dictionary(
            cachedTracks.flatMap(\.sources).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var dict: [String: MasterTrack] = [:]
        for source in fetched {
            MasterTrack.insert(
                source.preservingArtwork(from: cachedByKey[source.key]),
                into: &dict
            )
        }

        for old in cachedTracks {
            for source in old.sources {
                let provider = source.providerID
                // Keep only cached sources from a connected provider that failed
                // to return anything this cycle.
                if attempted.contains(provider) && !returned.contains(provider) {
                    MasterTrack.insert(source, into: &dict)
                }
            }
        }

        let merged = Array(dict.values)
        return LibraryProjection(
            tracks: merged,
            artists: MasterArtist.aggregate(merged)
        )
    }

    private nonisolated static func deepProjection(
        cachedTracks: [MasterTrack],
        fetched: [(UnifiedPlaylist, [UnifiedTrack])]
    ) -> LibraryProjection {
        var dict: [String: MasterTrack] = [:]
        for track in cachedTracks {
            for source in track.sources { MasterTrack.insert(source, into: &dict) }
        }
        for (_, playlistTracks) in fetched {
            for source in playlistTracks { MasterTrack.insert(source, into: &dict) }
        }
        let merged = Array(dict.values)
        return LibraryProjection(
            tracks: merged,
            artists: MasterArtist.aggregate(merged)
        )
    }

    private func persist() {
        guard let ownerID = hydratedOwnerID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        let snapshot = MasterLibrarySnapshot(tracks: tracks, artists: artists)
        Task.detached(priority: .utility) { snapshot.save(ownerID: ownerID) }
    }

    // MARK: - Federated search

    /// Debounced, cancellable entry point. Cancels any in-flight query, waits out
    /// the debounce, then runs the federated search. The View calls this on every
    /// keystroke; only the latest term's results ever render.
    func setSearch(
        _ term: String,
        localPlaylists: [UnifiedPlaylist],
        providerFilter: ProviderID? = nil
    ) {
        searchTerm = term
        searchTask?.cancel()

        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searching = false
            searchedWithNoProviders = false
            searchResults = SearchResults()
            return
        }

        // First paint is entirely local and synchronous. Keep network debounce
        // from turning a responsive indexed search into a blank spinner.
        searchResults = Self.localResults(
            query: query,
            tracks: tracks,
            playlists: localPlaylists
        )
        searching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            if Task.isCancelled { return }
            await self.runSearch(
                query,
                localPlaylists: localPlaylists,
                providerFilter: providerFilter
            )
        }
    }

    /// Run one query end-to-end and apply the result atomically. Stale checks
    /// (`Task.isCancelled`) guarantee an older query never overwrites a newer one.
    private func runSearch(
        _ query: String,
        localPlaylists: [UnifiedPlaylist],
        providerFilter: ProviderID?
    ) async {
        let connectedProviders = await ProviderRegistry.connected()
        let providers = connectedProviders.filter {
            providerFilter == nil || $0.id == providerFilter
        }
        if Task.isCancelled { return }

        // Publish cached matches immediately. Network providers and profiles then
        // refine the same stable result set without making local search wait.
        let localMatches = tracks
            .filter { Self.trackMatches($0, query: query) }
            .flatMap(\.sources)
        let localTracks = Self.rankTracks(MasterTrack.group(localMatches), query: query)
        let matchingPlaylists = Self.rankPlaylists(localPlaylists, query: query)
        searchResults = SearchResults(
            tracks: localTracks,
            artists: Self.rankArtists(localTracks, query: query),
            playlists: matchingPlaylists,
            people: []
        )
        searchedWithNoProviders = connectedProviders.isEmpty

        let shouldFindPeople = providerFilter == nil || providerFilter == .heartable
        async let peopleFetch: [FoundProfileDTO] = shouldFindPeople
            ? Self.findPeople(query)
            : []
        let found = await Self.gatherSearch(
            providers,
            query: query,
            defaultTimeout: providerSearchTimeout
        )
        if Task.isCancelled { return }

        // Merge federated hits into the local projection, de-dupe, and rank.
        let merged = MasterTrack.group(found + localMatches)
        let rankedTracks = Self.rankTracks(merged, query: query)
        let rankedArtists = Self.rankArtists(merged, query: query)
        let people = await peopleFetch
        if Task.isCancelled { return }

        searchResults = SearchResults(
            tracks: rankedTracks,
            artists: rankedArtists,
            playlists: matchingPlaylists,
            people: Self.rankPeople(people, query: query)
        )
        searchedWithNoProviders = connectedProviders.isEmpty
        searching = false
    }

    // MARK: - Concurrency helpers (off-actor, Sendable)

    private nonisolated static func gather(
        _ providers: [MusicProvider],
        _ op: @escaping @Sendable (MusicProvider) async -> [UnifiedTrack]
    ) async -> [UnifiedTrack] {
        await withTaskGroup(of: [UnifiedTrack].self) { group in
            for provider in providers { group.addTask { await op(provider) } }
            var all: [UnifiedTrack] = []
            for await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    /// Search every provider concurrently, each capped by a soft timeout so one
    /// slow service is dropped rather than stalling the merge. Provider adapters
    /// already return `[]` on failure, so failures are isolated too.
    private nonisolated static func gatherSearch(
        _ providers: [MusicProvider],
        query: String,
        defaultTimeout: TimeInterval
    ) async -> [UnifiedTrack] {
        await withTaskGroup(of: [UnifiedTrack].self) { group in
            for provider in providers {
                // MusicKit may need to wake its catalog session after launch.
                // Give Apple a wider first-search window instead of silently
                // presenting an empty provider-filtered result after six seconds.
                let timeout = provider.id == .apple ? 15 : defaultTimeout
                group.addTask { await timedSearch(provider, query, timeout) }
            }
            var all: [UnifiedTrack] = []
            for await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    /// Race a provider search against a timeout; the loser is cancelled.
    private nonisolated static func timedSearch(
        _ provider: MusicProvider,
        _ query: String,
        _ timeout: TimeInterval
    ) async -> [UnifiedTrack] {
        await withTaskGroup(of: [UnifiedTrack]?.self) { group in
            group.addTask { await provider.search(query) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    private nonisolated static func findPeople(_ query: String) async -> [FoundProfileDTO] {
        (try? await BackendAPI.shared.findProfiles(query: query)) ?? []
    }

    /// Bounded-concurrency fetch of every playlist's tracks (mirrors LibraryStore).
    private nonisolated static func gatherPlaylistTracks(
        _ playlists: [UnifiedPlaylist],
        maxConcurrent: Int
    ) async -> [(UnifiedPlaylist, [UnifiedTrack])] {
        await withTaskGroup(of: (UnifiedPlaylist, [UnifiedTrack]).self) { group in
            var results: [(UnifiedPlaylist, [UnifiedTrack])] = []
            var index = 0
            while index < playlists.count && index < maxConcurrent {
                let playlist = playlists[index]
                group.addTask { (playlist, await playlistTracks(playlist)) }
                index += 1
            }
            for await pair in group {
                results.append(pair)
                if index < playlists.count {
                    let playlist = playlists[index]
                    group.addTask { (playlist, await playlistTracks(playlist)) }
                    index += 1
                }
            }
            return results
        }
    }

    private nonisolated static func playlistTracks(_ playlist: UnifiedPlaylist) async -> [UnifiedTrack] {
        await ProviderRegistry.provider(for: playlist.providerID)
            .playlistTracks(playlist.playlistID)
    }

    // MARK: - Ranking

    private nonisolated static func localResults(
        query: String,
        tracks: [MasterTrack],
        playlists: [UnifiedPlaylist]
    ) -> SearchResults {
        let matches = tracks.filter { trackMatches($0, query: query) }
        let rankedTracks = rankTracks(matches, query: query)
        return SearchResults(
            tracks: rankedTracks,
            artists: rankArtists(rankedTracks, query: query),
            playlists: rankPlaylists(playlists, query: query),
            people: []
        )
    }

    /// Exact title match first, then title prefix, then artist prefix, then any
    /// substring; ties broken by provenance breadth (more services = more
    /// canonical) then title. Deterministic, so the applied list is stable.
    private nonisolated static func rankTracks(
        _ tracks: [MasterTrack],
        query: String
    ) -> [MasterTrack] {
        let q = normalizedSearchText(query)
        func score(_ track: MasterTrack) -> Int {
            let title = normalizedSearchText(track.title)
            let artist = normalizedSearchText(track.artistNames)
            if title == q { return 0 }
            if title.hasPrefix(q) { return 1 }
            if artist == q { return 2 }
            if artist.hasPrefix(q) { return 3 }
            if title.contains(q) { return 4 }
            return 5
        }
        return tracks.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa < sb }
            if a.providers.count != b.providers.count { return a.providers.count > b.providers.count }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private nonisolated static func rankArtists(
        _ tracks: [MasterTrack],
        query: String
    ) -> [MasterArtist] {
        let q = normalizedSearchText(query)
        func score(_ artist: MasterArtist) -> Int {
            let name = normalizedSearchText(artist.name)
            if name == q { return 0 }
            if name.hasPrefix(q) { return 1 }
            return 2
        }
        return MasterArtist.aggregate(tracks)
            .filter { normalizedSearchText($0.name).contains(q) }
            .sorted { lhs, rhs in
                let leftScore = score(lhs)
                let rightScore = score(rhs)
                if leftScore != rightScore { return leftScore < rightScore }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private nonisolated static func rankPlaylists(
        _ playlists: [UnifiedPlaylist],
        query: String
    ) -> [UnifiedPlaylist] {
        let q = normalizedSearchText(query)
        func score(_ playlist: UnifiedPlaylist) -> Int {
            let name = normalizedSearchText(playlist.name)
            if name == q { return 0 }
            if name.hasPrefix(q) { return 1 }
            return 2
        }
        return playlists
            .filter { normalizedSearchText($0.name).contains(q) }
            .sorted { lhs, rhs in
                let leftScore = score(lhs)
                let rightScore = score(rhs)
                if leftScore != rightScore { return leftScore < rightScore }
                if lhs.trackCount != rhs.trackCount {
                    return lhs.trackCount > rhs.trackCount
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private nonisolated static func rankPeople(
        _ people: [FoundProfileDTO],
        query: String
    ) -> [FoundProfileDTO] {
        let q = normalizedSearchText(query)
        return people.sorted { lhs, rhs in
            let left = normalizedSearchText(lhs.displayName ?? "")
            let right = normalizedSearchText(rhs.displayName ?? "")
            let leftScore = left == q ? 0 : (left.hasPrefix(q) ? 1 : 2)
            let rightScore = right == q ? 0 : (right.hasPrefix(q) ? 1 : 2)
            if leftScore != rightScore { return leftScore < rightScore }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private nonisolated static func trackMatches(
        _ track: MasterTrack,
        query: String
    ) -> Bool {
        let q = normalizedSearchText(query)
        return normalizedSearchText(track.title).contains(q)
            || normalizedSearchText(track.artistNames).contains(q)
    }

    private nonisolated static func normalizedSearchText(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Reset

    /// Forget everything (call on sign-out / account switch).
    func reset() {
        lifecycleID = UUID()
        searchTask?.cancel()
        searchTask = nil
        tracks = []
        artists = []
        searchResults = SearchResults()
        searchTerm = ""
        searching = false
        loadedProviders = []
        lastLoadedAt = nil
        didDeepIndex = false
        didHydrate = false
        hydratedOwnerID = nil
        searchedWithNoProviders = false
    }
}
