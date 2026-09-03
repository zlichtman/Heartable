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

    func play(_ track: UnifiedTrack) async throws
}

extension MusicProvider {
    func topTracks(range: StatRange = .mediumTerm, limit: Int = 25) async -> [UnifiedTrack] {
        await topTracks(range: range, limit: limit)
    }
    func likedTracks(limit: Int = 100) async -> [UnifiedTrack] {
        await likedTracks(limit: limit)
    }

    func connectionMetadata() async -> [String: String] { [:] }
    func restoreConnection(metadata: [String: String]) async {}
}

/// Thrown by adapters when an action can't proceed; message is user-facing.
struct ProviderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
