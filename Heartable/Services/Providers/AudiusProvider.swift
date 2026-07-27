import Foundation

/// Audius — a decentralized, open music network. Its API needs no developer
/// credentials and no per-user OAuth for public reads, and it hands out a direct
/// streamable URL per track. That makes it the one provider Heartable can fully play
/// *in-app* (via `LocalAudioEngine`) with zero setup, so "tap a song and it plays"
/// works the moment you enable it.
///
/// Reads that need a logged-in Audius account (your library, your playlists)
/// require their OAuth flow, which we haven't wired — those return empty for now.
/// Search, trending, public-playlist tracks, and playback all work unauthenticated.
/// Ported from the RN `audiusProvider` adapter.
struct AudiusProvider: MusicProvider {
    let id: ProviderID = .audius

    private static let app = "app_name=Heartable"
    private static let enabledKey = "heartable.audius.enabled"
    private static let fallbackHost = "https://discoveryprovider.audius.co"

    /// Audius is a network of discovery nodes; `api.audius.co` returns the healthy
    /// ones. We pick one per process and reuse it. The resolver is an actor so the
    /// chosen host is cached safely under strict concurrency.
    private actor HostResolver {
        static let shared = HostResolver()

        private var cached: String?
        private var inFlight: Task<String, Never>?

        func host() async -> String {
            if let cached { return cached }
            if let inFlight { return await inFlight.value }
            let task = Task<String, Never> { await Self.resolve() }
            inFlight = task
            let result = await task.value
            cached = result
            inFlight = nil
            return result
        }

        private static func resolve() async -> String {
            do {
                guard let url = URL(string: "https://api.audius.co") else {
                    return AudiusProvider.fallbackHost
                }
                let res: DiscoveryResponse = try await HTTPClient.getJSON(url)
                guard !res.data.isEmpty else { return AudiusProvider.fallbackHost }
                return res.data.randomElement() ?? AudiusProvider.fallbackHost
            } catch {
                return AudiusProvider.fallbackHost
            }
        }
    }

    // MARK: - Connection (an enable flag in UserDefaults; no account needed)

    func isConnected() async -> Bool {
        AccountSessionStore.defaultString(forKey: Self.enabledKey) == "1"
    }

    func connect() async throws {
        // No account or OAuth needed for public catalog + streaming — enabling
        // Audius just turns it on as a source.
        AccountSessionStore.setDefault("1", forKey: Self.enabledKey)
        // Warm the discovery-node pick so the first play is snappy.
        Task { _ = await HostResolver.shared.host() }
    }

    func disconnect() async {
        AccountSessionStore.removeDefault(forKey: Self.enabledKey)
        await MainActor.run {
            if LocalAudioEngine.shared.isCurrent(.audius) {
                LocalAudioEngine.shared.stop()
            }
        }
    }

    // MARK: - Reads (never throw — return [] on any failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let tracks = await get("/tracks/trending", params: "limit=\(limit)")
        return tracks.map(Self.mapTrack)
    }

    // Your Audius library/likes need their OAuth login, which isn't wired yet.
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }

    func playlists() async -> [UnifiedPlaylist] { [] }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let tracks = await get("/playlists/\(playlistID)/tracks")
        return tracks.map(Self.mapTrack)
    }

    func search(_ query: String) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        let tracks = await get("/tracks/search", params: "query=\(encoded)")
        return tracks.map(Self.mapTrack)
    }

    // MARK: - Playback (full track in-app via the local engine)

    func play(_ track: UnifiedTrack) async throws {
        let host = await HostResolver.shared.host()
        guard let streamURL = URL(
            string: "\(host)/v1/tracks/\(track.providerTrackID)/stream?\(Self.app)"
        ) else {
            throw ProviderError("Couldn't build the Audius stream URL.")
        }
        let meta = LocalAudioEngine.NowPlaying(
            key: track.key,
            providerID: .audius,
            uri: track.uri,
            trackID: track.providerTrackID,
            name: track.name,
            artist: track.artists.first?.name ?? "Audius",
            artworkURL: track.albumArt,
            durationMs: track.durationMs
        )
        await MainActor.run {
            LocalAudioEngine.shared.play(meta, url: streamURL)
        }
    }

    // MARK: - Networking

    /// GET `{host}/v1{path}?app_name=Heartable[&params]` and return the `data` array.
    /// Returns `[]` on bad URL / non-2xx / transport / decode failure.
    private func get(_ path: String, params: String = "") async -> [AudiusTrack] {
        let host = await HostResolver.shared.host()
        let sep = params.isEmpty ? "" : "&\(params)"
        guard let url = URL(string: "\(host)/v1\(path)?\(Self.app)\(sep)") else { return [] }
        do {
            let res: TrackListResponse = try await HTTPClient.getJSON(url)
            return res.data
        } catch {
            return []
        }
    }

    // MARK: - Mapping

    private static func mapTrack(_ t: AudiusTrack) -> UnifiedTrack {
        let id = t.id ?? ""
        let artists: [UnifiedArtist]
        if let user = t.user, let name = user.name {
            artists = [UnifiedArtist(id: user.id ?? user.handle ?? id, name: name)]
        } else {
            artists = []
        }
        return UnifiedTrack(
            key: trackKey(.audius, id),
            providerID: .audius,
            providerTrackID: id,
            uri: "audius:track:\(id)",
            name: t.title ?? "Untitled",
            artists: artists,
            album: nil,
            albumArt: t.artwork?.best.flatMap(URL.init(string:)),
            durationMs: Int((t.duration ?? 0) * 1000)
        )
    }
}

// MARK: - Decodable payloads

private struct DiscoveryResponse: Decodable {
    let data: [String]
}

private struct TrackListResponse: Decodable {
    let data: [AudiusTrack]
}

private struct AudiusTrack: Decodable {
    let id: String?
    let title: String?
    let duration: Double?
    let user: AudiusUser?
    let artwork: AudiusArtwork?
}

private struct AudiusUser: Decodable {
    let id: String?
    let name: String?
    let handle: String?
}

/// Audius returns artwork as a dict of size-keyed URLs. Prefer 480, then 1000,
/// then 150 (matching the RN `bestArt`).
private struct AudiusArtwork: Decodable {
    let size150: String?
    let size480: String?
    let size1000: String?

    var best: String? { size480 ?? size1000 ?? size150 }

    private enum CodingKeys: String, CodingKey {
        case size150 = "150x150"
        case size480 = "480x480"
        case size1000 = "1000x1000"
    }
}

private extension CharacterSet {
    /// `urlQueryAllowed` permits `&` and `=`, which would corrupt a single query
    /// value. This strips those so a search term encodes cleanly.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?+")
        return set
    }()
}
