import Foundation

/// WSUM's three official live streams. There is no account, enable flag, or
/// third-party directory lookup between selecting a station and starting audio.
struct WSUMProvider: MusicProvider {
    let id: ProviderID = .wsum

    func isConnected() async -> Bool { true }
    func connect() async throws {}
    func disconnect() async {}
    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] { [] }
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }
    func playlists() async -> [UnifiedPlaylist] { [] }
    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }
    func search(_ query: String) async -> [UnifiedTrack] { FeaturedRadioStations.search(query) }

    func play(_ track: UnifiedTrack) async throws {
        guard let station = FeaturedRadioStations.station(id: track.providerTrackID) else {
            throw ProviderError("This WSUM station is unavailable.")
        }
        let canonical = station.track
        try await LocalAudioEngine.shared.play(
            .init(key: canonical.key, providerID: id, uri: canonical.uri,
                  trackID: canonical.providerTrackID, name: canonical.name,
                  artist: "WSUM · Madison, Wisconsin", artworkURL: canonical.albumArt,
                  durationMs: 0),
            url: station.stream
        )
    }
}
