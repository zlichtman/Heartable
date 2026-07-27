import Foundation

/// Mixcloud — DJ mixes, radio shows, and podcasts. Its public API needs no key and
/// no per-user login for reads, so popular-now and search work the moment you enable
/// it. Playback, though, lives inside Mixcloud's own player (there's no reliable
/// direct stream URL), so Heartable stays honest: it surfaces the shows and hands
/// you off to Mixcloud to listen. Reads only, no in-app audio.
struct MixcloudProvider: MusicProvider {
    let id: ProviderID = .mixcloud

    private static let base = "https://api.mixcloud.com"
    private static let enabledKey = "heartable.mixcloud.enabled"

    // MARK: - Connection (an enable flag in UserDefaults; no account needed)

    func isConnected() async -> Bool {
        AccountSessionStore.defaultString(forKey: Self.enabledKey) == "1"
    }

    func connect() async throws {
        // Public reads need nothing — enabling Mixcloud just turns it on as a source.
        AccountSessionStore.setDefault("1", forKey: Self.enabledKey)
    }

    func disconnect() async {
        AccountSessionStore.removeDefault(forKey: Self.enabledKey)
    }

    // MARK: - Reads (never throw — return [] on any failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let clouds = await get("/popular/?limit=\(limit)")
        return clouds.map(Self.mapTrack)
    }

    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }

    func playlists() async -> [UnifiedPlaylist] { [] }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }

    func search(_ query: String) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        let clouds = await get("/search/?q=\(encoded)&type=cloudcast&limit=25")
        return clouds.map(Self.mapTrack)
    }

    // MARK: - Playback (none — streams live behind Mixcloud's own player)

    func play(_ track: UnifiedTrack) async throws {
        throw ProviderError("Mixcloud shows play on Mixcloud. Open it there to listen.")
    }

    // MARK: - Networking

    /// GET `{base}{path}` and return the `data` array. Returns `[]` on bad URL /
    /// non-2xx / transport / decode failure.
    private func get(_ path: String) async -> [Cloudcast] {
        guard let url = URL(string: "\(Self.base)\(path)") else { return [] }
        do {
            let res: CloudcastListResponse = try await HTTPClient.getJSON(url, decoder: HTTPClient.snakeCase)
            return res.data
        } catch {
            return []
        }
    }

    // MARK: - Mapping

    private static func mapTrack(_ c: Cloudcast) -> UnifiedTrack {
        let key = c.key ?? ""
        let handle = c.user?.username ?? ""
        let displayName = c.user?.name ?? handle
        let artists = handle.isEmpty ? [] : [UnifiedArtist(id: handle, name: displayName)]
        let art = (c.pictures?.large ?? c.pictures?.medium).flatMap(URL.init(string:))
        return UnifiedTrack(
            key: trackKey(.mixcloud, key),
            providerID: .mixcloud,
            providerTrackID: key,
            uri: "mixcloud:track:\(key)",
            name: c.name ?? "Untitled",
            artists: artists,
            album: nil,
            albumArt: art,
            durationMs: (c.audioLength ?? 0) * 1000
        )
    }
}

// MARK: - Decodable payloads

private struct CloudcastListResponse: Decodable {
    let data: [Cloudcast]
}

private struct Cloudcast: Decodable {
    /// Path key, e.g. `/user/show/` — Mixcloud's stable per-cloudcast identifier.
    let key: String?
    let name: String?
    let url: String?
    let user: CloudcastUser?
    let pictures: CloudcastPictures?
    /// Duration in whole seconds.
    let audioLength: Int?
}

private struct CloudcastUser: Decodable {
    let username: String?
    let name: String?
}

private struct CloudcastPictures: Decodable {
    let large: String?
    let medium: String?
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
