import Foundation

/// Radio Browser — a community directory of live internet-radio stations. The API
/// needs no key and no per-user login, and every station carries a resolved stream
/// URL. Heartable models each station as a track and plays the live stream in-app
/// via `LocalAudioEngine`, so enabling it works with zero setup (like Audius).
///
/// There's no user account, so personal liked/playlists have no meaning and return
/// empty. Top ("most clicked"), search, and playback all work unauthenticated. The
/// API asks clients to send a User-Agent and to register a "click" when a station
/// starts playing, both of which we do.
struct RadioBrowserProvider: MusicProvider {
    let id: ProviderID = .radioBrowser

    private static let enabledKey = "heartable.radioBrowser.enabled"
    private static let fallbackHost = "https://de1.api.radio-browser.info"
    private static let userAgent = "Heartable/1.0"
    private static let headers = ["User-Agent": userAgent]
    /// The protocol's `search` carries no limit, so cap results at a sensible page.
    private static let searchLimit = 50

    /// Radio Browser is a pool of mirrors; `all.api.radio-browser.info/json/servers`
    /// lists the healthy ones. We pick one per process and reuse it, falling back to
    /// the stable `de1` mirror. The resolver is an actor so the chosen host is cached
    /// safely under strict concurrency.
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
                guard let url = URL(string: "https://all.api.radio-browser.info/json/servers") else {
                    return RadioBrowserProvider.fallbackHost
                }
                let servers: [RBServer] = try await HTTPClient.getJSON(
                    url, headers: RadioBrowserProvider.headers
                )
                let names = servers.compactMap { $0.name }.filter { !$0.isEmpty }
                guard let pick = names.randomElement() else {
                    return RadioBrowserProvider.fallbackHost
                }
                return "https://\(pick)"
            } catch {
                return RadioBrowserProvider.fallbackHost
            }
        }
    }

    // MARK: - Connection (an enable flag in UserDefaults; no account needed)

    func isConnected() async -> Bool {
        AccountSessionStore.defaultString(forKey: Self.enabledKey) == "1"
    }

    func connect() async throws {
        // The open station directory + live streaming need nothing — enabling
        // Radio Browser just turns it on as a source.
        AccountSessionStore.setDefault("1", forKey: Self.enabledKey)
        // Warm the mirror pick so the first play is snappy.
        Task { _ = await HostResolver.shared.host() }
    }

    func disconnect() async {
        AccountSessionStore.removeDefault(forKey: Self.enabledKey)
        await MainActor.run {
            if LocalAudioEngine.shared.isCurrent(.radioBrowser) {
                LocalAudioEngine.shared.stop()
            }
        }
    }

    func restoreConnection(metadata: [String: String]) async {
        AccountSessionStore.setDefault("1", forKey: Self.enabledKey)
    }

    // MARK: - Reads (never throw — return [] on any failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        // Most-clicked stations; `range` has no analogue in the directory.
        let stations = await get("/json/stations/topclick/\(limit)")
        return stations.map(Self.mapStation)
    }

    // No Radio Browser user account, so there's nothing personal to pull.
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }

    func playlists() async -> [UnifiedPlaylist] { [] }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }

    func search(_ query: String) async -> [UnifiedTrack] {
        guard await isConnected() else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        let stations = await get(
            "/json/stations/search?name=\(encoded)&limit=\(Self.searchLimit)&hidebroken=true&order=clickcount&reverse=true"
        )
        return stations.map(Self.mapStation)
    }

    // MARK: - Playback (live stream through the in-app engine)

    func play(_ track: UnifiedTrack) async throws {
        let uuid = track.providerTrackID
        // Resolve a fresh stream URL at play time — stations come and go.
        let stations = await get("/json/stations/byuuid/\(uuid)")
        guard let resolved = stations.first?.urlResolved, !resolved.isEmpty,
              let url = URL(string: resolved) else {
            throw ProviderError("This station has no working stream right now.")
        }

        let nowPlaying = LocalAudioEngine.NowPlaying(
            key: track.key,
            providerID: .radioBrowser,
            uri: track.uri,
            trackID: track.providerTrackID,
            name: track.name,
            artist: track.artists.first?.name ?? "Radio",
            artworkURL: track.albumArt,
            // Live streams have no duration.
            durationMs: 0
        )
        await MainActor.run {
            LocalAudioEngine.shared.play(nowPlaying, url: url)
        }

        // Register a listen with the directory (best effort — never surface a failure).
        await Self.registerClick(uuid)
    }

    // MARK: - Networking

    /// GETs `{host}{path}` (path may include its own query) with the required
    /// User-Agent and decodes a station array. Returns `[]` on any failure.
    private func get(_ path: String) async -> [RBStation] {
        let host = await HostResolver.shared.host()
        guard let url = URL(string: "\(host)\(path)") else { return [] }
        do {
            return try await HTTPClient.getJSON(url, headers: Self.headers)
        } catch {
            return []
        }
    }

    /// Radio Browser's click endpoint bumps a station's popularity. Best effort:
    /// swallow every failure so it can never throw to the caller.
    private static func registerClick(_ uuid: String) async {
        let host = await HostResolver.shared.host()
        guard let url = URL(string: "\(host)/json/url/\(uuid)") else { return }
        _ = try? await HTTPClient.send(url, headers: headers)
    }

    // MARK: - Mapping

    private static func mapStation(_ s: RBStation) -> UnifiedTrack {
        let uuid = s.stationUUID ?? ""
        let country = s.country ?? ""
        let tags = s.tags ?? ""
        let label: String
        if !country.isEmpty { label = country }
        else if !tags.isEmpty { label = tags }
        else { label = "Radio" }

        let art: URL? = {
            guard let favicon = s.favicon, !favicon.isEmpty else { return nil }
            return URL(string: favicon)
        }()

        return UnifiedTrack(
            key: trackKey(.radioBrowser, uuid),
            providerID: .radioBrowser,
            providerTrackID: uuid,
            uri: "radio_browser:track:\(uuid)",
            name: s.name ?? "Radio Station",
            artists: [UnifiedArtist(id: country, name: label)],
            album: nil,
            albumArt: art,
            durationMs: 0
        )
    }
}

// MARK: - Decodable payloads

private struct RBServer: Decodable, Sendable {
    let name: String?
}

private struct RBStation: Decodable, Sendable {
    let stationUUID: String?
    let name: String?
    let urlResolved: String?
    let favicon: String?
    let country: String?
    let tags: String?
    let codec: String?
    let bitrate: Int?

    enum CodingKeys: String, CodingKey {
        case stationUUID = "stationuuid"
        case name
        case urlResolved = "url_resolved"
        case favicon
        case country
        case tags
        case codec
        case bitrate
    }
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
