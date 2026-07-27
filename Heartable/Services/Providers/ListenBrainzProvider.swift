import Foundation

/// ListenBrainz — MetaBrainz's open, non-commercial listening-history service (the
/// libre cousin of Last.fm). Like Last.fm it's a stats sidecar, not a player: it
/// doesn't stream audio, but it hands over long-window "top recordings" that a
/// streaming API won't. Public stats need only a username — no token, no API key —
/// which the user types in-app on connect (stored in UserDefaults).
///
/// `play()` throws on purpose — there's nothing to play. Cover art, when a
/// recording carries a Cover Art Archive release id, comes from coverartarchive.org.
struct ListenBrainzProvider: MusicProvider {
    let id: ProviderID = .listenbrainz

    private static let base = "https://api.listenbrainz.org/1"
    private static let userKey = "heartable.listenbrainz.user"

    /// The username stats are read for. Typed in-app; no Secrets fallback.
    static var username: String? {
        guard let stored = AccountSessionStore.defaultString(forKey: userKey) else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setUsername(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            AccountSessionStore.removeDefault(forKey: userKey)
        } else {
            AccountSessionStore.setDefault(trimmed, forKey: userKey)
        }
    }

    /// Maps Spotify's three ranges onto ListenBrainz's stat windows.
    private static func range(_ range: StatRange) -> String {
        switch range {
        case .shortTerm: "this_week"
        case .mediumTerm: "this_month"
        case .longTerm: "all_time"
        }
    }

    // MARK: - Connection (username typed in-app — no token, no enable flag)

    func isConnected() async -> Bool {
        Self.username != nil
    }

    func connect() async throws {
        guard Self.username != nil else {
            throw ProviderError("Enter your ListenBrainz username first.")
        }
    }

    func disconnect() async {
        Self.setUsername("")
    }

    // MARK: - Reads (never throw — return [] on any failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard let user = Self.username, let path = Self.userPath(user) else { return [] }
        guard let url = URL(string:
            "\(Self.base)/stats/user/\(path)/recordings?count=\(limit)&range=\(Self.range(range))"
        ) else { return [] }
        do {
            let res: StatsResponse = try await HTTPClient.getJSON(url, decoder: HTTPClient.snakeCase)
            return (res.payload?.recordings ?? []).map(Self.mapTrack)
        } catch {
            // A 204 (no stats yet) or an empty body decodes to nothing — treat as empty.
            return []
        }
    }

    // Loved tracks come back as bare recording mbids; resolving each to a title
    // needs a second round-trip per track, which we don't do. Return empty rather
    // than surface unlabeled rows.
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }

    func playlists() async -> [UnifiedPlaylist] { [] }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }

    // No public recording-search endpoint that maps cleanly to the unified track.
    func search(_ query: String) async -> [UnifiedTrack] { [] }

    // MARK: - Playback (none — it's a stats service)

    func play(_ track: UnifiedTrack) async throws {
        throw ProviderError("ListenBrainz is stats only. Play this song from a connected streaming service.")
    }

    // MARK: - Helpers

    /// Percent-encode the username for use as a path segment.
    private static func userPath(_ user: String) -> String? {
        user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    // MARK: - Mapping

    private static func mapTrack(_ r: StatRecording) -> UnifiedTrack {
        let id = r.recordingMbid ?? r.trackName ?? ""
        let name = r.trackName ?? "Unknown"
        let artistName = r.artistName ?? ""
        let artists = artistName.isEmpty ? [] : [UnifiedArtist(id: artistName, name: artistName)]
        let art = r.caaReleaseMbid.flatMap {
            URL(string: "https://coverartarchive.org/release/\($0)/front-250")
        }
        return UnifiedTrack(
            key: trackKey(.listenbrainz, id),
            providerID: .listenbrainz,
            providerTrackID: id,
            uri: "listenbrainz:track:\(id)",
            name: name,
            artists: artists,
            album: nil,
            albumArt: art,
            durationMs: 0
        )
    }
}

// MARK: - Decodable payloads

private struct StatsResponse: Decodable {
    let payload: StatsPayload?
}

private struct StatsPayload: Decodable {
    let recordings: [StatRecording]?
}

private struct StatRecording: Decodable {
    let trackName: String?
    let artistName: String?
    let recordingMbid: String?
    let releaseMbid: String?
    let caaReleaseMbid: String?
}
