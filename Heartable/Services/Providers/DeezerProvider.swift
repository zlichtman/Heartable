import Foundation

/// Deezer — its public REST API needs no credentials and no per-user OAuth for
/// public reads (search, charts, public playlists), and every track carries a
/// direct 30-second `preview` MP3. So, like Audius, Heartable can play Deezer
/// in-app immediately (the preview clip) with zero setup. Full-length playback
/// would need Deezer's deprecated native SDK, so previews are the honest ceiling.
///
/// Your Deezer library/likes/playlists need their OAuth login (a client secret
/// exchanged server-side) which isn't wired — those return empty for now.
struct DeezerProvider: MusicProvider {
    let id: ProviderID = .deezer

    private static let base = "https://api.deezer.com"
    private static let enabledKey = "heartable.deezer.enabled"

    // MARK: Connection (public catalog + previews need nothing; enable = a flag)

    func isConnected() async -> Bool {
        AccountSessionStore.defaultString(forKey: Self.enabledKey) == "1"
    }

    func connect() async throws {
        AccountSessionStore.setDefault("1", forKey: Self.enabledKey)
    }

    func disconnect() async {
        AccountSessionStore.removeDefault(forKey: Self.enabledKey)
        await MainActor.run {
            if LocalAudioEngine.shared.isCurrent(.deezer) {
                LocalAudioEngine.shared.stop()
            }
        }
    }

    func restoreConnection(metadata: [String: String]) async {
        AccountSessionStore.setDefault("1", forKey: Self.enabledKey)
    }

    // MARK: Reads (never throw — return [] on not-connected/failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let list: DZList? = await Self.get("/chart/0/tracks?limit=\(limit)")
        return (list?.data ?? []).map(Self.mapTrack)
    }

    // Your Deezer favourites/playlists need their OAuth login (not wired yet).
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }

    func playlists() async -> [UnifiedPlaylist] { [] }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let list: DZList? = await Self.get("/playlist/\(playlistID)/tracks")
        return (list?.data ?? []).map(Self.mapTrack)
    }

    func search(_ query: String) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? query
        let list: DZList? = await Self.get("/search?q=\(encoded)")
        return (list?.data ?? []).map(Self.mapTrack)
    }

    // MARK: Playback (30s preview through the in-app engine)

    func play(_ track: UnifiedTrack) async throws {
        // Fetch a fresh preview URL (they expire) and stream the 30s clip in-app.
        let full: DZTrack? = await Self.get("/track/\(track.providerTrackID)")
        guard let preview = full?.preview, !preview.isEmpty, let url = URL(string: preview) else {
            throw ProviderError("No preview available for this Deezer track.")
        }
        await MainActor.run {
            LocalAudioEngine.shared.play(
                .init(
                    key: track.key,
                    providerID: .deezer,
                    uri: track.uri,
                    trackID: track.providerTrackID,
                    name: track.name,
                    artist: track.artists.first?.name ?? "Deezer",
                    artworkURL: track.albumArt,
                    durationMs: track.durationMs
                ),
                url: url
            )
        }
    }

    // MARK: HTTP

    /// GETs `base + path`, returning nil on transport/status error or a Deezer
    /// `error` object (their API returns 200 with `{error:{...}}` on failure).
    private static func get<T: Decodable & Sendable>(_ path: String) async -> T? {
        guard let url = URL(string: base + path) else { return nil }
        do {
            // One round-trip: fetch the bytes, check Deezer's 200-with-{error} shape,
            // then decode the payload from the same data.
            let (data, resp) = try await HTTPClient.send(url)
            guard (200..<300).contains(resp.statusCode) else { return nil }
            if let probe = try? JSONDecoder().decode(DZErrorProbe.self, from: data),
               probe.error != nil { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: Mapping

    private static func mapTrack(_ t: DZTrack) -> UnifiedTrack {
        let id = String(t.id)
        let artists: [UnifiedArtist] = {
            guard let artist = t.artist, let name = artist.name else { return [] }
            let artistID = artist.id.map(String.init) ?? name
            return [UnifiedArtist(id: artistID, name: name)]
        }()
        return UnifiedTrack(
            key: trackKey(.deezer, id),
            providerID: .deezer,
            providerTrackID: id,
            // Stable handle — the (expiring) preview URL is re-fetched at play time.
            uri: "deezer:track:\(id)",
            name: t.title ?? "Untitled",
            artists: artists,
            album: t.album?.title,
            albumArt: Self.cover(t.album),
            durationMs: Int((t.duration ?? 0).rounded()) * 1000
        )
    }

    private static func cover(_ album: DZAlbum?) -> URL? {
        let best = album?.coverXl ?? album?.coverBig ?? album?.coverMedium ?? album?.cover
        guard let best, !best.isEmpty else { return nil }
        return URL(string: best)
    }
}

// MARK: - Decodable payloads

private struct DZErrorProbe: Decodable, Sendable {
    let error: DZError?
    struct DZError: Decodable, Sendable {}
}

private struct DZList: Decodable, Sendable {
    let data: [DZTrack]?
}

private struct DZTrack: Decodable, Sendable {
    let id: Int
    let title: String?
    let duration: Double?
    let preview: String?
    let artist: DZArtist?
    let album: DZAlbum?
}

private struct DZArtist: Decodable, Sendable {
    let id: Int?
    let name: String?
}

private struct DZAlbum: Decodable, Sendable {
    let title: String?
    let cover: String?
    let coverMedium: String?
    let coverBig: String?
    let coverXl: String?

    enum CodingKeys: String, CodingKey {
        case title
        case cover
        case coverMedium = "cover_medium"
        case coverBig = "cover_big"
        case coverXl = "cover_xl"
    }
}

private extension CharacterSet {
    /// Percent-encodes a query *value* — `urlQueryAllowed` leaves `&`/`+`/`=`
    /// intact, which would corrupt a search term. This is the JS `encodeURIComponent` posture.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?/")
        return set
    }()
}
