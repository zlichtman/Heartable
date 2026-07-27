import Foundation

/// Last.fm — a stats sidecar, not a player. It doesn't stream audio; what it's
/// great at is long-window listening history (all-time / multi-month top tracks,
/// loved tracks) that Spotify's API won't give you. Read-only, public data, so
/// it needs only a free instant API key (`LASTFM_API_KEY` in Secrets — from
/// last.fm/api/account/create) plus a username, which the user types in-app on
/// connect (stored in UserDefaults; `LASTFM_USER` in Secrets is the fallback).
///
/// `play()` throws on purpose — there's nothing to play. Ported from the RN
/// `lastfmProvider` adapter.
///
/// The wrinkle here is that Last.fm's JSON is loose: the `artist` field is an
/// object (`{name}` / `{"#text"}`) in top/loved tracks but a bare string in
/// search; and the `track` list collapses to a single object instead of an array
/// when there's exactly one result. The Decodable types below absorb both shapes.
struct LastfmProvider: MusicProvider {
    let id: ProviderID = .lastfm

    private static let base = "https://ws.audioscrobbler.com/2.0/"
    private static let userKey = "heartable.lastfm.user"
    private static let enabledKey = "heartable.lastfm.enabled"

    private static let setupMessage =
        "Add LASTFM_API_KEY (free at last.fm/api) to Secrets.xcconfig, then rebuild."

    /// The username stats are read for: in-app entry wins, Secrets is the fallback.
    static var username: String? {
        if let stored = AccountSessionStore.defaultString(forKey: userKey),
           !stored.trimmingCharacters(in: .whitespaces).isEmpty {
            return stored.trimmingCharacters(in: .whitespaces)
        }
        return AppConfig.lastfmUser
    }

    static func setUsername(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            AccountSessionStore.removeDefault(forKey: userKey)
        } else {
            AccountSessionStore.setDefault(trimmed, forKey: userKey)
        }
    }

    /// Maps Spotify's three ranges onto the closest Last.fm periods.
    private static func period(_ range: StatRange) -> String {
        switch range {
        case .shortTerm: "1month"
        case .mediumTerm: "6month"
        case .longTerm: "overall"
        }
    }

    private var configured: Bool {
        AppConfig.lastfmAPIKey != nil && Self.username != nil
    }

    // MARK: - Connection (key from Secrets, username typed in-app, enable = a flag)

    func isConnected() async -> Bool {
        configured && AccountSessionStore.defaultString(forKey: Self.enabledKey) == "1"
    }

    func connect() async throws {
        guard AppConfig.lastfmAPIKey != nil else { throw ProviderError(Self.setupMessage) }
        guard Self.username != nil else {
            throw ProviderError("Add your Last.fm username first.")
        }
        AccountSessionStore.setDefault("1", forKey: Self.enabledKey)
    }

    func disconnect() async {
        // Keep the username so reconnecting is one tap.
        AccountSessionStore.removeDefault(forKey: Self.enabledKey)
    }

    // MARK: - Reads (never throw — return [] on any failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        let res: TopTracksResponse? = await call([
            "method": "user.gettoptracks",
            "user": Self.username ?? "",
            "period": Self.period(range),
            "limit": String(limit),
        ])
        return (res?.toptracks?.track.values ?? []).map(Self.mapTrack)
    }

    func likedTracks(limit: Int) async -> [UnifiedTrack] {
        let res: LovedTracksResponse? = await call([
            "method": "user.getlovedtracks",
            "user": Self.username ?? "",
            "limit": String(limit),
        ])
        return (res?.lovedtracks?.track.values ?? []).map(Self.mapTrack)
    }

    // Last.fm playlists were deprecated years ago.
    func playlists() async -> [UnifiedPlaylist] { [] }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }

    func search(_ query: String) async -> [UnifiedTrack] {
        let res: SearchResponse? = await call([
            "method": "track.search",
            "track": query,
            "limit": "20",
        ])
        return (res?.results?.trackmatches?.track.values ?? []).map(Self.mapTrack)
    }

    // MARK: - Playback (none — it's a stats service)

    func play(_ track: UnifiedTrack) async throws {
        throw ProviderError("Last.fm is a stats service. It doesn't play music.")
    }

    // MARK: - Networking

    /// GET `base?{params}&api_key=…&format=json` and decode `T`. Returns `nil`
    /// on not-configured / bad URL / non-2xx / transport / decode failure — every
    /// data method maps `nil` to `[]`, so nothing throws to the UI.
    private func call<T: Decodable>(_ params: [String: String]) async -> T? {
        guard let apiKey = AppConfig.lastfmAPIKey, configured else { return nil }

        var comps = URLComponents(string: Self.base)
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        items.append(URLQueryItem(name: "format", value: "json"))
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }

        return try? await HTTPClient.getJSON(url)
    }

    // MARK: - Mapping

    private static func mapTrack(_ t: LastfmTrack) -> UnifiedTrack {
        let artistName = t.artist?.name ?? ""
        let name = t.name ?? "Unknown"
        let mbid = t.mbid ?? ""
        let id = mbid.isEmpty ? "\(artistName)::\(name)" : mbid
        let artists = artistName.isEmpty ? [] : [UnifiedArtist(id: artistName, name: artistName)]
        let durationSeconds = Int(t.duration ?? "") ?? 0

        return UnifiedTrack(
            key: trackKey(.lastfm, id),
            providerID: .lastfm,
            providerTrackID: id,
            uri: "lastfm:track:\(id)",
            name: name,
            artists: artists,
            album: nil,
            albumArt: Self.bestImage(t.image).flatMap(URL.init(string:)),
            durationMs: durationSeconds * 1000
        )
    }

    /// Prefer the largest non-empty image url, falling back to the first present.
    private static func bestImage(_ images: [LastfmImage]?) -> String? {
        guard let images, !images.isEmpty else { return nil }
        for size in ["extralarge", "large", "medium", "small"] {
            if let match = images.first(where: { $0.size == size && !($0.text?.isEmpty ?? true) }),
               let text = match.text {
                return text
            }
        }
        return images.first(where: { !($0.text?.isEmpty ?? true) })?.text
    }
}

// MARK: - Decodable payloads

private struct TopTracksResponse: Decodable {
    let toptracks: TrackContainer?
}

private struct LovedTracksResponse: Decodable {
    let lovedtracks: TrackContainer?
}

private struct SearchResponse: Decodable {
    let results: SearchResults?
}

private struct SearchResults: Decodable {
    let trackmatches: TrackContainer?
}

private struct TrackContainer: Decodable {
    let track: FlexibleArray<LastfmTrack>
}

private struct LastfmTrack: Decodable {
    let name: String?
    let mbid: String?
    /// String of whole seconds in top/loved responses; absent in search.
    let duration: String?
    let artist: FlexibleArtist?
    let image: [LastfmImage]?
}

private struct LastfmImage: Decodable {
    let text: String?
    let size: String?

    private enum CodingKeys: String, CodingKey {
        case text = "#text"
        case size
    }
}

/// Last.fm's `artist` is an object (`{name}` / `{"#text"}`) in top/loved tracks
/// but a bare string in search. Decode whichever shape arrived; expose `name`.
private struct FlexibleArtist: Decodable {
    let name: String?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let str = try? single.decode(String.self) {
            name = str.isEmpty ? nil : str
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .text)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case text = "#text"
    }
}

/// Last.fm collapses a one-element list to a single object instead of an array.
/// Decode either: try the array first, then fall back to a single value, then
/// to empty. `values` is the normalized array the mappers consume.
private struct FlexibleArray<Element: Decodable>: Decodable {
    let values: [Element]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([Element].self) {
            values = array
        } else if let single = try? container.decode(Element.self) {
            values = [single]
        } else {
            values = []
        }
    }
}
