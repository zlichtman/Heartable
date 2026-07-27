import Foundation

/// Jellyfin — open-source self-hosted media server. Like Plex this is your own
/// library, not a cloud catalog, but there's no central account at all: the user
/// enters their server address plus username/password in-app, and we hold the
/// session token the server mints. Reads go through `/Items`; playback uses the
/// `/Audio/{id}/universal` endpoint, which direct-streams anything AVPlayer can
/// decode and transcodes to HLS otherwise — so Jellyfin tracks play **in-app**
/// through `LocalAudioEngine`, full length.
///
/// Unlike Plex, Jellyfin exposes per-user favorites cleanly (`Filters=IsFavorite`),
/// so all five capabilities light up: top, liked, playlists, search, playback.
struct JellyfinProvider: MusicProvider {
    let id: ProviderID = .jellyfin

    private static let keyToken = "heartable_jellyfin_token"
    private static let serverKey = "heartable.jellyfin.server"
    private static let userIDKey = "heartable.jellyfin.userId"
    private static let usernameKey = "heartable.jellyfin.username"
    private static let deviceIDKey = "heartable.jellyfin.deviceId"

    /// Everything a call to the server needs: base URL, session token, user id.
    private struct Session: Sendable {
        let base: String
        let token: String
        let userID: String
    }

    private static func session(ownerID: UUID? = AccountSessionStore.currentOwnerID) -> Session? {
        guard let ownerID,
              let token = AccountSessionStore.keychainValue(
                  forKey: keyToken,
                  ownerID: ownerID
              ),
              let base = AccountSessionStore.defaultString(
                  forKey: serverKey,
                  ownerID: ownerID
              ),
              let userID = AccountSessionStore.defaultString(
                  forKey: userIDKey,
                  ownerID: ownerID
              ) else { return nil }
        return Session(base: base, token: token, userID: userID)
    }

    /// Prefills for the connect sheet (kept across disconnects; never the password).
    static var storedServer: String? { AccountSessionStore.defaultString(forKey: serverKey) }
    static var storedUsername: String? { AccountSessionStore.defaultString(forKey: usernameKey) }

    // MARK: - Connection (server address + sign-in, typed in-app)

    func isConnected() async -> Bool {
        Self.session() != nil
    }

    /// The connect sheet does the real work via `link`; the protocol-level connect
    /// only validates that a session exists (mirrors the Last.fm/ListenBrainz shape).
    func connect() async throws {
        guard Self.session() != nil else {
            throw ProviderError("Enter your Jellyfin server address and sign in first.")
        }
    }

    /// Signs in to the server and stores the session. Throws user-facing messages
    /// for every failure class: bad address, unreachable, wrong credentials.
    static func link(server rawServer: String, username rawUsername: String, password: String) async throws {
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            throw ProviderError("Sign in to Heartable before connecting Jellyfin.")
        }
        guard let base = normalizeServerURL(rawServer) else {
            throw ProviderError("Enter your server address, like http://192.168.1.20:8096.")
        }
        let username = rawUsername.trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty else {
            throw ProviderError("Enter your Jellyfin username.")
        }
        guard let url = URL(string: base + "/Users/AuthenticateByName") else {
            throw ProviderError("That server address doesn't look right.")
        }
        let body = try? JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        do {
            let (data, resp) = try await HTTPClient.send(url, method: "POST", headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": authHeader(),
            ], body: body)
            if resp.statusCode == 401 {
                throw ProviderError("Wrong username or password.")
            }
            guard (200..<300).contains(resp.statusCode) else {
                throw ProviderError("The server said no (\(resp.statusCode)). Check the address and try again.")
            }
            guard let auth = try? HTTPClient.json.decode(AuthResponse.self, from: data),
                  let token = auth.accessToken, !token.isEmpty,
                  let userID = auth.user?.id, !userID.isEmpty else {
                throw ProviderError("That address didn't answer like a Jellyfin server.")
            }
            guard AccountSessionStore.currentOwnerID == ownerID else {
                throw ProviderError(
                    "Your Heartable session changed. Connect Jellyfin again."
                )
            }
            AccountSessionStore.setKeychainValue(
                token,
                forKey: keyToken,
                ownerID: ownerID
            )
            AccountSessionStore.setDefault(base, forKey: serverKey, ownerID: ownerID)
            AccountSessionStore.setDefault(userID, forKey: userIDKey, ownerID: ownerID)
            AccountSessionStore.setDefault(
                username,
                forKey: usernameKey,
                ownerID: ownerID
            )
        } catch let e as ProviderError {
            throw e
        } catch {
            throw ProviderError("Couldn't reach the server. Check the address and that it's online.")
        }
    }

    func disconnect() async {
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        // Best-effort server-side logout so the session doesn't linger in the
        // Jellyfin dashboard; local cleanup happens regardless.
        if let s = Self.session(ownerID: ownerID),
           let url = URL(string: s.base + "/Sessions/Logout") {
            _ = try? await HTTPClient.send(url, method: "POST", headers: [
                "Authorization": Self.authHeader(token: s.token),
            ])
        }
        AccountSessionStore.deleteKeychainValue(
            forKey: Self.keyToken,
            ownerID: ownerID
        )
        AccountSessionStore.removeDefault(
            forKey: Self.userIDKey,
            ownerID: ownerID
        )
        await MainActor.run {
            if LocalAudioEngine.shared.isCurrent(.jellyfin) {
                LocalAudioEngine.shared.stop()
            }
        }
    }

    // MARK: - Reads (never throw — return [] on not-connected/failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard let s = Self.session() else { return [] }
        let resp: ItemsResponse? = await Self.get(s, path: "/Items", query: [
            "userId": s.userID,
            "IncludeItemTypes": "Audio",
            "Recursive": "true",
            "SortBy": "PlayCount,SortName",
            "SortOrder": "Descending",
            "Limit": "\(limit)",
        ])
        return (resp?.items ?? []).map { Self.mapTrack($0, session: s) }
    }

    func likedTracks(limit: Int) async -> [UnifiedTrack] {
        guard let s = Self.session() else { return [] }
        let resp: ItemsResponse? = await Self.get(s, path: "/Items", query: [
            "userId": s.userID,
            "IncludeItemTypes": "Audio",
            "Recursive": "true",
            "Filters": "IsFavorite",
            "SortBy": "SortName",
            "SortOrder": "Ascending",
            "Limit": "\(limit)",
        ])
        return (resp?.items ?? []).map { Self.mapTrack($0, session: s) }
    }

    func playlists() async -> [UnifiedPlaylist] {
        guard let s = Self.session() else { return [] }
        let resp: ItemsResponse? = await Self.get(s, path: "/Items", query: [
            "userId": s.userID,
            "IncludeItemTypes": "Playlist",
            "Recursive": "true",
            "SortBy": "SortName",
            "SortOrder": "Ascending",
            "Limit": "10000",
        ])
        return (resp?.items ?? []).map { Self.mapPlaylist($0, session: s) }
    }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] {
        guard let s = Self.session() else { return [] }
        let resp: ItemsResponse? = await Self.get(
            s,
            path: "/Playlists/\(playlistID)/Items",
            query: ["userId": s.userID, "Limit": "10000"]
        )
        return (resp?.items ?? []).map { Self.mapTrack($0, session: s) }
    }

    func search(_ query: String) async -> [UnifiedTrack] {
        guard let s = Self.session() else { return [] }
        let resp: ItemsResponse? = await Self.get(s, path: "/Items", query: [
            "userId": s.userID,
            "IncludeItemTypes": "Audio",
            "Recursive": "true",
            "SearchTerm": query,
            "Limit": "50",
        ])
        return (resp?.items ?? []).map { Self.mapTrack($0, session: s) }
    }

    // MARK: - Playback (full track in-app via the local engine)

    func play(_ track: UnifiedTrack) async throws {
        guard let s = Self.session() else {
            throw ProviderError("Jellyfin isn't connected.")
        }
        // `/universal` direct-streams containers AVPlayer decodes natively and
        // falls back to an HLS transcode for anything else (ogg/opus/wma), so
        // every library track is playable and seekable.
        var comps = URLComponents(string: s.base + "/Audio/\(track.providerTrackID)/universal")
        comps?.queryItems = [
            URLQueryItem(name: "userId", value: s.userID),
            URLQueryItem(name: "deviceId", value: Self.deviceIdentifier()),
            URLQueryItem(name: "api_key", value: s.token),
            URLQueryItem(name: "container", value: "mp3,aac,m4a,m4b,flac,alac,wav,aiff"),
            URLQueryItem(name: "audioCodec", value: "aac"),
            URLQueryItem(name: "transcodingContainer", value: "ts"),
            URLQueryItem(name: "transcodingProtocol", value: "hls"),
            URLQueryItem(name: "maxStreamingBitrate", value: "140000000"),
        ]
        guard let streamURL = comps?.url else {
            throw ProviderError("Couldn't build the Jellyfin stream URL.")
        }
        let meta = LocalAudioEngine.NowPlaying(
            key: track.key,
            providerID: .jellyfin,
            uri: track.uri,
            trackID: track.providerTrackID,
            name: track.name,
            artist: track.artists.first?.name ?? "Jellyfin",
            artworkURL: track.albumArt,
            durationMs: track.durationMs
        )
        await MainActor.run {
            LocalAudioEngine.shared.play(meta, url: streamURL)
        }
    }

    // MARK: - Server address normalization

    /// Accepts what people actually type — `192.168.1.20:8096`, `nas.local:8096`,
    /// `jellyfin.example.com`, a full URL, with or without a trailing slash or a
    /// reverse-proxy subpath. Bare LAN targets (IP literals, `.local`, single-label
    /// hosts) default to http, since Jellyfin's out-of-box port 8096 is plain http;
    /// bare public domains default to https.
    static func normalizeServerURL(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            let hostPart = s.split(separator: "/").first.map(String.init) ?? s
            let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
            let isIPv4 = !host.isEmpty && host.allSatisfy { $0.isNumber || $0 == "." }
            let isLocal = host.hasSuffix(".local") || !host.contains(".")
            s = (isIPv4 || isLocal ? "http://" : "https://") + s
        }
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        guard let url = URL(string: s), let scheme = url.scheme, let host = url.host,
              (scheme == "http" || scheme == "https"), !host.isEmpty else { return nil }
        return s
    }

    // MARK: - Client identity + headers

    /// Stable per-install device id — names this session in the Jellyfin dashboard
    /// and keys the transcode session on stream URLs.
    private static func deviceIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: deviceIDKey)
        return new
    }

    /// The `MediaBrowser` scheme Jellyfin expects: client identity on every call,
    /// plus the session token once signed in.
    private static func authHeader(token: String? = nil) -> String {
        var parts = [
            "Client=\"Heartable\"",
            "Device=\"iPhone\"",
            "DeviceId=\"\(deviceIdentifier())\"",
            "Version=\"1.0\"",
        ]
        if let token { parts.append("Token=\"\(token)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    // MARK: - Server networking

    /// GET `{base}{path}` with the session token, decoding JSON. Returns nil on
    /// bad URL / non-2xx / transport / decode failure (reads swallow it).
    private static func get<T: Decodable & Sendable>(
        _ session: Session, path: String, query: [String: String]
    ) async -> T? {
        var comps = URLComponents(string: session.base + path)
        comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps?.url else { return nil }
        do {
            let decoded: T = try await HTTPClient.getJSON(url, headers: [
                "Accept": "application/json",
                "Authorization": authHeader(token: session.token),
            ])
            return decoded
        } catch {
            return nil
        }
    }

    // MARK: - Mapping

    private static func mapTrack(_ item: JFItem, session: Session) -> UnifiedTrack {
        let id = item.id ?? ""
        let artists: [UnifiedArtist]
        if let items = item.artistItems, !items.isEmpty {
            artists = items.compactMap { a in
                guard let name = a.name, !name.isEmpty else { return nil }
                return UnifiedArtist(id: a.id ?? name, name: name)
            }
        } else {
            artists = (item.artists ?? []).map { UnifiedArtist(id: $0, name: $0) }
        }
        return UnifiedTrack(
            key: trackKey(.jellyfin, id),
            providerID: .jellyfin,
            providerTrackID: id,
            uri: "jellyfin:track:\(id)",
            name: item.name ?? "Untitled",
            artists: artists,
            album: item.album,
            albumArt: artURL(item: item, session: session),
            durationMs: Int((item.runTimeTicks ?? 0) / 10_000)   // 100ns ticks → ms
        )
    }

    private static func mapPlaylist(_ item: JFItem, session: Session) -> UnifiedPlaylist {
        let id = item.id ?? ""
        return UnifiedPlaylist(
            key: "\(ProviderID.jellyfin.rawValue):\(id)",
            providerID: .jellyfin,
            playlistID: id,
            name: item.name ?? "Playlist",
            description: nil,
            image: artURL(item: item, session: session),
            trackCount: item.childCount ?? 0,
            owner: nil
        )
    }

    /// Primary art for the item itself, else the parent album's. The tag pins the
    /// exact image version so server/CDN caching works; api_key covers servers
    /// that require auth for images.
    private static func artURL(item: JFItem, session: Session) -> URL? {
        let target: (id: String, tag: String)?
        if let id = item.id, let tag = item.imageTags?["Primary"] {
            target = (id, tag)
        } else if let albumID = item.albumId, let tag = item.albumPrimaryImageTag {
            target = (albumID, tag)
        } else {
            target = nil
        }
        guard let target else { return nil }
        var comps = URLComponents(string: session.base + "/Items/\(target.id)/Images/Primary")
        comps?.queryItems = [
            URLQueryItem(name: "tag", value: target.tag),
            URLQueryItem(name: "maxWidth", value: "600"),
            URLQueryItem(name: "quality", value: "90"),
            URLQueryItem(name: "api_key", value: session.token),
        ]
        return comps?.url
    }
}

// MARK: - Decodable payloads (Jellyfin JSON is strict PascalCase)

private struct AuthResponse: Decodable, Sendable {
    let accessToken: String?
    let user: JFUser?
    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

private struct JFUser: Decodable, Sendable {
    let id: String?
    enum CodingKeys: String, CodingKey { case id = "Id" }
}

private struct ItemsResponse: Decodable, Sendable {
    let items: [JFItem]?
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct JFItem: Decodable, Sendable {
    let id: String?
    let name: String?
    let album: String?
    let albumId: String?
    let albumPrimaryImageTag: String?
    let artists: [String]?
    let artistItems: [JFArtistRef]?
    let runTimeTicks: Int64?
    let imageTags: [String: String]?
    let childCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case album = "Album"
        case albumId = "AlbumId"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag"
        case artists = "Artists"
        case artistItems = "ArtistItems"
        case runTimeTicks = "RunTimeTicks"
        case imageTags = "ImageTags"
        case childCount = "ChildCount"
    }
}

private struct JFArtistRef: Decodable, Sendable {
    let id: String?
    let name: String?
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}
