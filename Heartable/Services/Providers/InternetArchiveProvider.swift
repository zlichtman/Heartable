import Foundation

/// Internet Archive — the audio collection at archive.org is fully open: no
/// developer key, no per-user login, and every item exposes a direct file URL.
/// Heartable models each audio *item* as one track and streams its first playable
/// file in-app via `LocalAudioEngine`, so enabling it means "tap a song and it
/// plays" with zero setup (like Audius).
///
/// There's no user account here, so personal liked/playlists have no meaning and
/// return empty. Popularity ("top"), search, and playback all work unauthenticated.
struct InternetArchiveProvider: MusicProvider {
    let id: ProviderID = .internetArchive

    private static let searchBase = "https://archive.org/advancedsearch.php"

    // Public search sources are available without an account or enable flag.
    func isConnected() async -> Bool { true }
    func connect() async throws {}
    func disconnect() async {}

    // MARK: - Reads (never throw — return [] on any failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] { [] }

    // No Internet Archive user account, so there's nothing personal to pull.
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }

    func playlists() async -> [UnifiedPlaylist] { [] }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }

    func search(_ query: String) async -> [UnifiedTrack] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        let q = "\(encoded)+AND+mediatype:(audio)"
        let docs = await Self.advancedSearch(q: q, sort: nil, limit: 25)
        return docs.compactMap(Self.mapDoc)
    }

    // MARK: - Playback (first playable file streamed in-app via the local engine)

    func play(_ track: UnifiedTrack) async throws {
        let identifier = track.providerTrackID
        guard let metaURL = URL(string: "https://archive.org/metadata/\(identifier)") else {
            throw ProviderError("Couldn't build the Internet Archive metadata URL.")
        }

        let meta: IAMetadata
        do {
            meta = try await HTTPClient.getJSON(metaURL)
        } catch {
            throw ProviderError("Couldn't load this item from the Internet Archive.")
        }

        let files = meta.files ?? []
        // Prefer a VBR MP3, then any MP3, then an Ogg — the widely streamable formats.
        func hasFormat(_ file: IAFile, _ needle: String) -> Bool {
            (file.format ?? "").range(of: needle, options: .caseInsensitive) != nil
        }
        let chosen = files.first(where: { hasFormat($0, "VBR MP3") })
            ?? files.first(where: { hasFormat($0, "MP3") })
            ?? files.first(where: { hasFormat($0, "Ogg") })

        guard let file = chosen, let name = file.name, !name.isEmpty else {
            throw ProviderError("This item has no streamable audio.")
        }

        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let streamURL = URL(
            string: "https://archive.org/download/\(identifier)/\(encodedName)"
        ) else {
            throw ProviderError("Couldn't build the Internet Archive stream URL.")
        }

        let nowPlaying = LocalAudioEngine.NowPlaying(
            key: track.key,
            providerID: .internetArchive,
            uri: track.uri,
            trackID: track.providerTrackID,
            name: track.name,
            artist: track.artists.first?.name ?? "Internet Archive",
            artworkURL: track.albumArt,
            durationMs: track.durationMs
        )
        try await LocalAudioEngine.shared.play(nowPlaying, url: streamURL)
    }

    // MARK: - Networking

    /// GETs the advanced-search endpoint and returns the `response.docs`.
    /// `q` is a fully-formed Lucene query, already percent-encoded where needed.
    /// Returns `[]` on bad URL / non-2xx / transport / decode failure.
    private static func advancedSearch(q: String, sort: String?, limit: Int) async -> [IADoc] {
        // Brackets in `fl[]` / `sort[]` are pre-encoded so the RFC 3986 URL
        // parser accepts the string.
        var str = "\(searchBase)?q=\(q)"
        str += "&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator"
        if let sort { str += "&sort%5B%5D=\(sort)" }
        str += "&rows=\(limit)&page=1&output=json"
        guard let url = URL(string: str) else { return [] }
        do {
            let res: IAAdvancedSearchResponse = try await HTTPClient.getJSON(url)
            return res.response.docs ?? []
        } catch {
            return []
        }
    }

    // MARK: - Mapping

    private static func mapDoc(_ doc: IADoc) -> UnifiedTrack? {
        guard let identifier = doc.identifier, !identifier.isEmpty else { return nil }
        let artists: [UnifiedArtist]
        if let creator = doc.creator?.value, !creator.isEmpty {
            artists = [UnifiedArtist(id: creator, name: creator)]
        } else {
            artists = []
        }
        return UnifiedTrack(
            key: trackKey(.internetArchive, identifier),
            providerID: .internetArchive,
            providerTrackID: identifier,
            uri: "internet_archive:track:\(identifier)",
            name: doc.title ?? "Untitled",
            artists: artists,
            album: nil,
            albumArt: URL(string: "https://archive.org/services/img/\(identifier)"),
            durationMs: 0
        )
    }
}

// MARK: - Decodable payloads

private struct IAAdvancedSearchResponse: Decodable, Sendable {
    let response: IAResponseBody
}

private struct IAResponseBody: Decodable, Sendable {
    let docs: [IADoc]?
}

private struct IADoc: Decodable, Sendable {
    let identifier: String?
    let title: String?
    let creator: IACreator?
}

/// `creator` comes back as either a single string or an array of strings depending
/// on the item, so decode both shapes into one first-non-empty value.
private struct IACreator: Decodable, Sendable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            value = single
        } else if let many = try? container.decode([String].self) {
            value = many.first { !$0.isEmpty }
        } else {
            value = nil
        }
    }
}

private struct IAMetadata: Decodable, Sendable {
    let files: [IAFile]?
}

private struct IAFile: Decodable, Sendable {
    let name: String?
    let format: String?
    let length: String?
}

private extension CharacterSet {
    /// Percent-encodes a query *value* — `urlQueryAllowed` leaves `&`/`+`/`=`/`?`
    /// intact, which would corrupt a single query value. This strips those so a
    /// search term encodes cleanly.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?+")
        return set
    }()
}
