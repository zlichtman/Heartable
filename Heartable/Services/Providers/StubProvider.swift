import Foundation

/// Placeholder for catalog entries without an adapter. Reads return empty;
/// connect/play explain it's unavailable.
struct StubProvider: MusicProvider {
    let id: ProviderID

    func isConnected() async -> Bool { false }
    func connect() async throws {
        throw ProviderError("\(ProviderCatalog.label(for: id)) isn't available yet.")
    }
    func disconnect() async {}
    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] { [] }
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }
    func playlists() async -> [UnifiedPlaylist] { [] }
    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }
    func search(_ query: String) async -> [UnifiedTrack] { [] }
    func play(_ track: UnifiedTrack) async throws {
        throw ProviderError("Can't play \(id.rawValue) tracks yet.")
    }
}
