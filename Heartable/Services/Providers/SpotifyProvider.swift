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
        // A fresh grant is the user asking for their library now; a cooldown
        // recorded by an earlier burst must not silently outlive it.
        await SpotifyReadBackoff.shared.clear()
    }

    func disconnect() async {
        await SpotifyAuth.clearSession()
    }

    func connectionMetadata() async -> [String: String] {
        guard let owner = AccountSessionStore.currentOwnerID,
              let token = await SpotifyAuth.getValidAccessToken(),
              let user = try? await SpotifyAPI.me(token: token),
              AccountSessionStore.currentOwnerID == owner else { return [:] }
        var metadata = ["provider_user_id": user.id]
        if let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            metadata["display_name"] = name
        }
        if let photo = user.images?.compactMap(\.url).first,
           URL(string: photo)?.scheme == "https" { metadata["avatar_url"] = photo }
        return metadata
    }

    // MARK: - Reads

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        await readTopTracks(range: range, limit: limit).items ?? []
    }

    func readTopTracks(range: StatRange, limit: Int) async -> ProviderRead<UnifiedTrack> {
        guard let token = await SpotifyAuth.getValidAccessToken() else { return .unavailable }
        do {
            return .success(try await SpotifyAPI.topTracks(token: token, range: range, limit: limit)
                .map(Self.mapTrack))
        } catch {
            return .unavailable
        }
    }

    func likedTracks(limit: Int) async -> [UnifiedTrack] {
        await readLikedTracks(limit: limit).items ?? []
    }

    func readLikedTracks(limit: Int) async -> ProviderRead<UnifiedTrack> {
        await readLikedTracks(limit: limit, onPage: { _ in })
    }

    func readLikedTracks(limit: Int, onPage: @escaping @Sendable ([UnifiedTrack]) async -> Void) async -> ProviderRead<UnifiedTrack> {
        guard let token = await SpotifyAuth.getValidAccessToken() else { return .unavailable }
        do {
            return .success(try await SpotifyAPI.readSavedTrackPages(
                token: token, limit: limit, transform: Self.mapTrack, onPage: onPage
            ))
        } catch {
            return .unavailable
        }
    }

    func playlists() async -> [UnifiedPlaylist] {
        await readPlaylists().items ?? []
    }

    func readPlaylists() async -> ProviderRead<UnifiedPlaylist> {
        guard let token = await SpotifyAuth.getValidAccessToken() else { return .unavailable }
        do {
            return .success(try await SpotifyAPI.myPlaylists(token: token, limit: 10_000)
                .map(Self.mapPlaylist))
        } catch {
            return .unavailable
        }
    }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] {
        await readPlaylistTracks(playlistID).items ?? []
    }

    func readPlaylistTracks(_ playlistID: String) async -> ProviderRead<UnifiedTrack> {
        guard let token = await SpotifyAuth.getValidAccessToken() else {
            return .failure("Spotify couldn’t refresh your session. Check your connection, then reconnect Spotify in Music Services if this continues.")
        }
        do {
            let tracks = try await SpotifyAPI.readPlaylistTrackPages(
                token: token, id: playlistID, transform: Self.mapTrack
            )
            spotifyLog.info("playlistTracks(\(playlistID, privacy: .public)): \(tracks.count) tracks")
            return .success(tracks)
        } catch {
            if error is CancellationError { return .unavailable }
            let message = SpotifyPlaylistFailure.message(for: error)
            await SpotifyPlaylistFailure.record(error)
            return .failure(message)
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

    static func mapTrack(_ t: SpotifyTrack) -> UnifiedTrack {
        let artists = (t.artists ?? []).map {
            UnifiedArtist(id: $0.id ?? "", name: $0.name ?? "")
        }
        let artURL = t.album?.images?.first?.url.flatMap(URL.init(string:))
        return UnifiedTrack(
            key: trackKey(.spotify, t.id.isEmpty ? t.uri : t.id),
            providerID: .spotify,
            providerTrackID: t.id,
            uri: t.uri,
            name: t.name,
            artists: artists,
            album: t.album?.name,
            albumArt: artURL,
            durationMs: max(0, t.durationMs ?? 0),
            playbackUnavailableReason: t.isLocal ? "Local file · unavailable in Heartable"
                : (t.isPlayable == false || t.restrictionReason != nil ? "Unavailable on Spotify" : nil)
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
