import Foundation
import OSLog

private let spotifyLog = Logger(subsystem: "com.zlichtman.heartable", category: "spotify")

/// Spotify — the flagship live provider. Wraps PKCE auth (`SpotifyAuth`) and the
/// Web API client (`SpotifyAPI`) and normalizes everything to the unified model.
/// Ported from the RN `spotifyProvider` adapter.
///
/// Playback stays inside Heartable's UI and targets an available Spotify Connect
/// device. A missing device remains a typed error so the app can present its
/// in-app device picker instead of unexpectedly sending the user to Spotify.
struct SpotifyProvider: MusicProvider {
    let id: ProviderID = .spotify

    // MARK: - Connection

    /// Connected == a session exists (refresh token held). Deliberately does NOT
    /// fetch a live access token: a transient refresh failure must not look like a
    /// disconnect. The session only ends when Spotify rejects the refresh token.
    func isConnected() async -> Bool {
        SpotifyAuth.isSignedIn
    }

    func connect() async throws {
        try await SpotifyAuth.signIn()
    }

    func disconnect() async {
        await SpotifyAuth.clearSession()
    }

    // MARK: - Reads (never throw — return [] on not-connected/failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard let token = await SpotifyAuth.getValidAccessToken() else { return [] }
        do {
            return try await SpotifyAPI.topTracks(token: token, range: range, limit: limit)
                .map(Self.mapTrack)
        } catch {
            return []
        }
    }

    func likedTracks(limit: Int) async -> [UnifiedTrack] {
        guard let token = await SpotifyAuth.getValidAccessToken() else { return [] }
        do {
            return try await SpotifyAPI.savedTracks(token: token, limit: limit)
                .map(Self.mapTrack)
        } catch {
            return []
        }
    }

    func playlists() async -> [UnifiedPlaylist] {
        guard let token = await SpotifyAuth.getValidAccessToken() else { return [] }
        do {
            return try await SpotifyAPI.myPlaylists(token: token, limit: 10_000)
                .map(Self.mapPlaylist)
        } catch {
            return []
        }
    }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] {
        guard let token = await SpotifyAuth.getValidAccessToken() else {
            spotifyLog.error("playlistTracks(\(playlistID, privacy: .public)): no valid access token")
            return []
        }
        do {
            let tracks = try await SpotifyAPI.playlistTracks(token: token, id: playlistID)
                .map(Self.mapTrack)
            spotifyLog.info("playlistTracks(\(playlistID, privacy: .public)): \(tracks.count) tracks")
            return tracks
        } catch {
            spotifyLog.error("playlistTracks(\(playlistID, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func search(_ query: String) async -> [UnifiedTrack] {
        guard let token = await SpotifyAuth.getValidAccessToken() else { return [] }
        do {
            return try await SpotifyAPI.search(token: token, q: query, limit: 10)
                .map(Self.mapTrack)
        } catch {
            return []
        }
    }

    // MARK: - Playback

    func play(_ track: UnifiedTrack) async throws {
        try await startSpotifyPlayback(uris: [track.uri])
    }

    // MARK: - Mapping

    private static func mapTrack(_ t: SpotifyTrack) -> UnifiedTrack {
        let artists = (t.artists ?? []).map {
            UnifiedArtist(id: $0.id ?? "", name: $0.name ?? "")
        }
        let artURL = t.album?.images?.first?.url.flatMap(URL.init(string:))
        return UnifiedTrack(
            key: trackKey(.spotify, t.id),
            providerID: .spotify,
            providerTrackID: t.id,
            uri: t.uri,
            name: t.name,
            artists: artists,
            album: t.album?.name,
            albumArt: artURL,
            durationMs: t.durationMs ?? 0
        )
    }

    private static func mapPlaylist(_ p: SpotifyPlaylist) -> UnifiedPlaylist {
        UnifiedPlaylist(
            key: "\(ProviderID.spotify.rawValue):\(p.id)",
            providerID: .spotify,
            playlistID: p.id,
            name: p.name,
            description: p.description,
            image: p.images?.first?.url.flatMap(URL.init(string:)),
            trackCount: p.tracks?.total ?? 0,
            owner: p.owner?.displayName,
            contentRevision: p.snapshotID
        )
    }
}

/// Start Spotify playback for a set of URIs on an available Connect device.
/// Missing-device handling belongs to PlayerStore so all entry points get the
/// same in-app recovery flow.
func startSpotifyPlayback(uris: [String]) async throws {
    guard let token = await SpotifyAuth.getValidAccessToken() else {
        throw ProviderError("Spotify isn't connected.")
    }
    try await SpotifyAPI.play(token: token, uris: uris)
}
