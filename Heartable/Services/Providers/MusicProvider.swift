import Foundation

/// One connected (or connectable) music service. Adapters normalize their
/// native APIs into the unified model. Data reads return empty on
/// not-connected/failure (never throw to the UI); `connect()` and `play()`
/// throw a user-facing message. Ported from the RN `MusicProvider` interface.
protocol MusicProvider: Sendable {
    var id: ProviderID { get }

    func isConnected() async -> Bool
    func connect() async throws
    func disconnect() async

    /// Non-secret values that let another installation restore the account's
    /// connection intent. OAuth tokens and passwords must never be returned.
    func connectionMetadata() async -> [String: String]

    /// Apply account-owned connection intent before the local availability probe.
    /// Token providers remain unavailable when Keychain has no credential, which
    /// ProvidersStore reports as "reconnect required" rather than disconnected.
    func restoreConnection(metadata: [String: String]) async

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack]
    func likedTracks(limit: Int) async -> [UnifiedTrack]
    func playlists() async -> [UnifiedPlaylist]
    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack]
    func search(_ query: String) async -> [UnifiedTrack]

    /// Cache writes require a successful read, not just an array. A failed read
    /// must never be interpreted as an empty library or a deleted playlist.
    func readTopTracks(range: StatRange, limit: Int) async -> ProviderRead<UnifiedTrack>
    func readLikedTracks(limit: Int) async -> ProviderRead<UnifiedTrack>
    func readPlaylists() async -> ProviderRead<UnifiedPlaylist>
    func readPlaylistTracks(_ playlistID: String) async -> ProviderRead<UnifiedTrack>

    func play(_ track: UnifiedTrack) async throws
}

extension MusicProvider {
    // Legacy adapters still conflate empty and failed reads. Until they expose a
    // typed result, conservatively retain the last-good data on empty responses.
    func readTopTracks(range: StatRange, limit: Int) async -> ProviderRead<UnifiedTrack> {
        .legacy(await topTracks(range: range, limit: limit))
    }
    func readLikedTracks(limit: Int) async -> ProviderRead<UnifiedTrack> {
        .legacy(await likedTracks(limit: limit))
    }
    func readPlaylists() async -> ProviderRead<UnifiedPlaylist> {
        .legacy(await playlists())
    }
    func readPlaylistTracks(_ playlistID: String) async -> ProviderRead<UnifiedTrack> {
        .legacy(await playlistTracks(playlistID))
    }
    func topTracks(range: StatRange = .mediumTerm, limit: Int = 25) async -> [UnifiedTrack] {
        await topTracks(range: range, limit: limit)
    }
    func likedTracks(limit: Int = 100) async -> [UnifiedTrack] {
        await likedTracks(limit: limit)
    }

    func connectionMetadata() async -> [String: String] { [:] }
    func restoreConnection(metadata: [String: String]) async {}
}

enum ProviderRead<Element: Sendable>: Sendable {
    case success([Element])
    case unavailable

    var items: [Element]? {
        if case .success(let items) = self { return items }
        return nil
    }

    static func legacy(_ items: [Element]) -> Self {
        items.isEmpty ? .unavailable : .success(items)
    }
}

enum ProviderCacheMerge {
    /// Replace only the provider that succeeded. An authoritative empty response
    /// clears that provider; an unavailable response keeps its previous rows.
    static func merge<Element: Sendable>(
        cached: [Element], providers: [ProviderID],
        reads: [ProviderID: ProviderRead<Element>],
        providerID: (Element) -> ProviderID
    ) -> [Element] {
        providers.flatMap { id in
            reads[id]?.items ?? cached.filter { providerID($0) == id }
        }
    }

    static func gather<Element: Sendable>(
        _ providers: [MusicProvider],
        _ read: @escaping @Sendable (MusicProvider) async -> ProviderRead<Element>
    ) async -> [ProviderID: ProviderRead<Element>] {
        await withTaskGroup(of: (ProviderID, ProviderRead<Element>).self) { group in
            for provider in providers { group.addTask { (provider.id, await read(provider)) } }
            var results: [ProviderID: ProviderRead<Element>] = [:]
            for await (id, result) in group { results[id] = result }
            return results
        }
    }
}

/// Thrown by adapters when an action can't proceed; message is user-facing.
struct ProviderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
