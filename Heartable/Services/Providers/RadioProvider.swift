import Foundation

/// Playback for the curated live station catalog. Existing WSUM identities remain
/// compatible; other stations use the generic radio identity.
struct RadioProvider: MusicProvider {
    let id: ProviderID

    func isConnected() async -> Bool { true }
    func connect() async throws {}
    func disconnect() async {}
    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] { [] }
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }
    func playlists() async -> [UnifiedPlaylist] { [] }
    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }
    func search(_ query: String) async -> [UnifiedTrack] { [] }

    func play(_ track: UnifiedTrack) async throws {
        guard let station = FeaturedRadioStations.station(id: track.providerTrackID),
              station.providerID == id else {
            throw ProviderError("This radio station is unavailable.")
        }
        let canonical = station.track
        try await LocalAudioEngine.shared.play(
            .init(key: canonical.key, providerID: id, uri: canonical.uri,
                  trackID: canonical.providerTrackID, name: canonical.name,
                  artist: station.location, artworkURL: canonical.albumArt,
                  durationMs: 0),
            url: station.stream
        )
    }
}
