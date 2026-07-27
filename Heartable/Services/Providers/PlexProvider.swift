import AuthenticationServices
import Foundation
import UIKit

/// Plex — your own self-hosted music library. Unlike the cloud services, there's no
/// central catalog: you sign in to your Plex account (a PIN-link flow through the
/// hosted auth page), we discover your Plex Media Server, and read the music library
/// straight off it. Because the server hands back a direct file URL per track,
/// Heartable plays Plex tracks **in-app** through `LocalAudioEngine` — full length,
/// your files, no preview ceiling.
///
/// There's no per-user OAuth secret and no developer approval: the account link is a
/// short-lived PIN, and the server access token comes back with the resource list.
/// Personal "liked" state isn't cleanly exposed, so likedTracks returns empty.
struct PlexProvider: MusicProvider {
    let id: ProviderID = .plex

    private static let keyToken = "heartable_plex_token"
    private static let clientIDKey = "heartable.plex.clientIdentifier"
    private static let callbackScheme = "heartable"

    /// A chosen Plex Media Server: the base URL we talk to and the access token that
    /// authorizes reads/streams against it (distinct from the account token).
    struct PlexServer: Sendable {
        let baseURL: String
        let accessToken: String
    }

    /// Plex is a personal server behind an account. `resources` returns the servers
    /// linked to the account; we pick one and cache its base URL + access token, plus
    /// the music section key, so every read/play reuses the same resolved server. The
    /// resolver is an actor so the cache is safe under strict concurrency, and it's
    /// keyed off the account token so a reconnect re-resolves cleanly.
    private actor ServerResolver {
        static let shared = ServerResolver()

        private var cached: (token: String, server: PlexServer)?
        private var inFlight: Task<PlexServer?, Never>?
        private var cachedSection: (base: String, key: String)?

        func server(token: String) async -> PlexServer? {
            if let cached, cached.token == token { return cached.server }
            if let inFlight { return await inFlight.value }
            let task = Task<PlexServer?, Never> { await Self.resolve(token: token) }
            inFlight = task
            let result = await task.value
            inFlight = nil
            if let result { cached = (token, result) }
            return result
        }

        /// The first music library ("artist"-typed section) on the server, cached.
        func musicSectionKey(for server: PlexServer) async -> String? {
            if let cachedSection, cachedSection.base == server.baseURL { return cachedSection.key }
            guard let key = await Self.fetchMusicSectionKey(server: server) else { return nil }
            cachedSection = (server.baseURL, key)
            return key
        }

        func clear() {
            cached = nil
            cachedSection = nil
            inFlight?.cancel()
            inFlight = nil
        }

        private static func resolve(token: String) async -> PlexServer? {
            guard let url = URL(string: "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1") else {
                return nil
            }
            do {
                let resources: [PlexResource] = try await HTTPClient.getJSON(
                    url, headers: PlexProvider.plexHeaders(token: token)
                )
                let servers = resources.filter { ($0.provides ?? "").contains("server") }
                guard let server = servers.first else { return nil }
                let conns = server.connections ?? []
                // Prefer a direct, non-relay https connection; fall back to a relay
                // (works from anywhere but is slower), then to anything at all.
                let chosen = conns.first { $0.relay != true && ($0.uri?.hasPrefix("https") ?? false) }
                    ?? conns.first { $0.relay == true }
                    ?? conns.first
                guard let uri = chosen?.uri, !uri.isEmpty else { return nil }
                let base = uri.hasSuffix("/") ? String(uri.dropLast()) : uri
                let accessToken = server.accessToken ?? chosen?.accessToken ?? token
                return PlexServer(baseURL: base, accessToken: accessToken)
            } catch {
                return nil
            }
        }

        private static func fetchMusicSectionKey(server: PlexServer) async -> String? {
            let resp: SectionsResponse? = await PlexProvider.get(
                server: server, path: "/library/sections", query: [:]
            )
            return resp?.mediaContainer.directory?.first { $0.type == "artist" }?.key
        }
    }

    // MARK: - Connection (PIN link → account token in Keychain)

    /// Connected == an account token is held. Reads/streams resolve the server lazily.
    func isConnected() async -> Bool {
        AccountSessionStore.keychainValue(forKey: Self.keyToken) != nil
    }

    /// Links a Plex account: create a PIN, present the hosted auth page, then poll the
    /// PIN until Plex attaches the account token. Throws a user-facing error on
    /// cancel/timeout/failure.
    func connect() async throws {
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            throw ProviderError("Sign in to Heartable before connecting Plex.")
        }
        let clientID = Self.clientIdentifier()
        let pin = try await Self.createPin()

        // The hosted auth page is fragment-addressed (`/auth#?...`) and forwards to our
        // custom scheme when the user finishes, which closes the web session.
        let forward = "heartable://plex-linked"
        let encodedForward = forward.addingPercentEncoding(withAllowedCharacters: .plexForwardAllowed) ?? forward
        let authString = "https://app.plex.tv/auth#?clientID=\(clientID)"
            + "&code=\(pin.code)"
            + "&context%5Bdevice%5D%5Bproduct%5D=Heartable"
            + "&forwardUrl=\(encodedForward)"
        guard let authURL = URL(string: authString) else {
            throw ProviderError("Couldn't build the Plex sign-in URL.")
        }

        // Present the sign-in. Whether the user completes the forward or dismisses the
        // sheet, the account token is obtained by polling the PIN, so a cancel here is
        // not fatal on its own — the poll loop decides.
        _ = try? await PlexWebAuth.start(url: authURL, scheme: Self.callbackScheme)

        let token = try await Self.pollForToken(pinID: pin.id)
        guard AccountSessionStore.currentOwnerID == ownerID else {
            throw ProviderError("Your Heartable session changed. Connect Plex again.")
        }
        AccountSessionStore.setKeychainValue(
            token,
            forKey: Self.keyToken,
            ownerID: ownerID
        )
        // Warm server discovery so the first read/play is snappy.
        _ = await ServerResolver.shared.server(token: token)
    }

    func disconnect() async {
        AccountSessionStore.deleteKeychainValue(forKey: Self.keyToken)
        await ServerResolver.shared.clear()
        await MainActor.run {
            if LocalAudioEngine.shared.isCurrent(.plex) {
                LocalAudioEngine.shared.stop()
            }
        }
    }

    // MARK: - Reads (never throw — return [] on not-connected/failure)

    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        guard let server = await resolvedServer(),
              let sectionKey = await ServerResolver.shared.musicSectionKey(for: server) else { return [] }
        let resp: MetadataResponse? = await Self.get(
            server: server,
            path: "/library/sections/\(sectionKey)/all",
            query: ["type": "10", "sort": "viewCount:desc", "limit": "\(limit)"]
        )
        return (resp?.mediaContainer.metadata ?? []).map { Self.mapTrack($0, server: server) }
    }

    // Plex's per-user rating state isn't cleanly exposed for a whole-library pull.
    func likedTracks(limit: Int) async -> [UnifiedTrack] { [] }

    func playlists() async -> [UnifiedPlaylist] {
        guard let server = await resolvedServer() else { return [] }
        let resp: MetadataResponse? = await Self.get(
            server: server,
            path: "/playlists",
            query: [
                "playlistType": "audio",
                "X-Plex-Container-Start": "0",
                "X-Plex-Container-Size": "10000",
            ]
        )
        return (resp?.mediaContainer.metadata ?? []).map { Self.mapPlaylist($0, server: server) }
    }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] {
        guard let server = await resolvedServer() else { return [] }
        let resp: MetadataResponse? = await Self.get(
            server: server,
            path: "/playlists/\(playlistID)/items",
            query: [
                "X-Plex-Container-Start": "0",
                "X-Plex-Container-Size": "10000",
            ]
        )
        return (resp?.mediaContainer.metadata ?? []).map { Self.mapTrack($0, server: server) }
    }

    func search(_ query: String) async -> [UnifiedTrack] {
        guard let server = await resolvedServer(),
              let sectionKey = await ServerResolver.shared.musicSectionKey(for: server) else { return [] }
        let resp: MetadataResponse? = await Self.get(
            server: server,
            path: "/library/sections/\(sectionKey)/search",
            query: ["type": "10", "query": query]
        )
        return (resp?.mediaContainer.metadata ?? []).map { Self.mapTrack($0, server: server) }
    }

    // MARK: - Playback (full track in-app via the local engine)

    func play(_ track: UnifiedTrack) async throws {
        guard let token = AccountSessionStore.keychainValue(forKey: Self.keyToken) else {
            throw ProviderError("Plex isn't connected.")
        }
        guard let server = await ServerResolver.shared.server(token: token) else {
            throw ProviderError("Couldn't reach your Plex server. Check that it's online and try again.")
        }
        // Re-fetch the item to get its current stream part (the ratingKey is stable,
        // the file part path is what LocalAudioEngine plays).
        let resp: MetadataResponse? = await Self.get(
            server: server, path: "/library/metadata/\(track.providerTrackID)", query: [:]
        )
        guard let partKey = resp?.mediaContainer.metadata?.first?.media?.first?.part?.first?.key,
              !partKey.isEmpty else {
            throw ProviderError("This Plex track has no playable file.")
        }
        var comps = URLComponents(string: server.baseURL + partKey)
        comps?.queryItems = [URLQueryItem(name: "X-Plex-Token", value: server.accessToken)]
        guard let streamURL = comps?.url else {
            throw ProviderError("Couldn't build the Plex stream URL.")
        }
        let meta = LocalAudioEngine.NowPlaying(
            key: track.key,
            providerID: .plex,
            uri: track.uri,
            trackID: track.providerTrackID,
            name: track.name,
            artist: track.artists.first?.name ?? "Plex",
            artworkURL: track.albumArt,
            durationMs: track.durationMs
        )
        await MainActor.run {
            LocalAudioEngine.shared.play(meta, url: streamURL)
        }
    }

    // MARK: - Server resolution helper

    private func resolvedServer() async -> PlexServer? {
        guard let token = AccountSessionStore.keychainValue(forKey: Self.keyToken) else { return nil }
        return await ServerResolver.shared.server(token: token)
    }

    // MARK: - PIN link

    private static func createPin() async throws -> PlexPin {
        guard let url = URL(string: "https://plex.tv/api/v2/pins?strong=true") else {
            throw ProviderError("Couldn't reach Plex.")
        }
        do {
            let (data, resp) = try await HTTPClient.send(url, method: "POST", headers: plexHeaders())
            guard (200..<300).contains(resp.statusCode) else {
                throw ProviderError("Plex sign-in couldn't start. Please try again.")
            }
            return try JSONDecoder().decode(PlexPin.self, from: data)
        } catch let e as ProviderError {
            throw e
        } catch {
            throw ProviderError("Couldn't reach Plex. Check your connection and try again.")
        }
    }

    /// Polls the PIN until Plex attaches the account token, or times out.
    private static func pollForToken(pinID: Int) async throws -> String {
        for _ in 0..<12 {
            if let token = await checkPin(pinID: pinID), !token.isEmpty {
                return token
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw ProviderError("Plex sign-in was cancelled or timed out.")
    }

    private static func checkPin(pinID: Int) async -> String? {
        guard let url = URL(string: "https://plex.tv/api/v2/pins/\(pinID)") else { return nil }
        do {
            let pin: PlexPin = try await HTTPClient.getJSON(url, headers: plexHeaders())
            return pin.authToken
        } catch {
            return nil
        }
    }

    // MARK: - Client identity + headers

    /// A stable per-install identifier Plex uses to name this device. Persisted so the
    /// linked device stays the same across launches.
    private static func clientIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: clientIDKey) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: clientIDKey)
        return new
    }

    /// Standard plex.tv headers. Pass the account token for authorized calls
    /// (resource discovery); omit it for the unauthenticated PIN calls.
    fileprivate static func plexHeaders(token: String? = nil) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-Plex-Product": "Heartable",
            "X-Plex-Version": "1.0",
            "X-Plex-Client-Identifier": clientIdentifier(),
            "X-Plex-Platform": "iOS",
        ]
        if let token { headers["X-Plex-Token"] = token }
        return headers
    }

    // MARK: - Server networking

    /// GET `{base}{path}` with the server access token as a query param, decoding JSON.
    /// Returns nil on bad URL / non-2xx / transport / decode failure (reads swallow it).
    fileprivate static func get<T: Decodable & Sendable>(
        server: PlexServer, path: String, query: [String: String]
    ) async -> T? {
        var comps = URLComponents(string: server.baseURL + path)
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "X-Plex-Token", value: server.accessToken))
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }
        do {
            let decoded: T = try await HTTPClient.getJSON(url, headers: ["Accept": "application/json"])
            return decoded
        } catch {
            return nil
        }
    }

    // MARK: - Mapping

    private static func mapTrack(_ m: PlexMetadata, server: PlexServer) -> UnifiedTrack {
        let id = m.ratingKey ?? ""
        let artists: [UnifiedArtist]
        if let name = m.grandparentTitle, !name.isEmpty {
            artists = [UnifiedArtist(id: m.grandparentRatingKey ?? name, name: name)]
        } else {
            artists = []
        }
        return UnifiedTrack(
            key: trackKey(.plex, id),
            providerID: .plex,
            providerTrackID: id,
            uri: "plex:track:\(id)",
            name: m.title ?? "Untitled",
            artists: artists,
            album: m.parentTitle,
            albumArt: artURL(server: server, thumb: m.thumb ?? m.parentThumb ?? m.grandparentThumb),
            durationMs: m.duration ?? 0   // Plex reports track duration in milliseconds.
        )
    }

    private static func mapPlaylist(_ m: PlexMetadata, server: PlexServer) -> UnifiedPlaylist {
        let id = m.ratingKey ?? ""
        return UnifiedPlaylist(
            key: "\(ProviderID.plex.rawValue):\(id)",
            providerID: .plex,
            playlistID: id,
            name: m.title ?? "Playlist",
            description: nil,
            image: artURL(server: server, thumb: m.composite ?? m.thumb),
            trackCount: m.leafCount ?? 0,
            owner: nil
        )
    }

    /// Plex art paths are server-relative and need the access token to load.
    private static func artURL(server: PlexServer, thumb: String?) -> URL? {
        guard let thumb, !thumb.isEmpty else { return nil }
        var comps = URLComponents(string: server.baseURL + thumb)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "X-Plex-Token", value: server.accessToken))
        comps?.queryItems = items
        return comps?.url
    }
}

// MARK: - ASWebAuthenticationSession bridge

/// Bridges `ASWebAuthenticationSession` to async/await with a presentation anchor
/// pinned to the foreground key window. Mirrors `SpotifyAuth`'s `WebAuth`: the helper
/// retains itself until the callback fires. Plex-specific messages.
@MainActor
private final class PlexWebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var retain: PlexWebAuth?

    static func start(url: URL, scheme: String) async throws -> URL {
        let helper = PlexWebAuth()
        return try await helper.run(url: url, scheme: scheme)
    }

    private func run(url: URL, scheme: String) async throws -> URL {
        retain = self
        defer { retain = nil }
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: ProviderError("Plex connection was cancelled."))
                    } else {
                        cont.resume(throwing: ProviderError(error.localizedDescription))
                    }
                } else {
                    cont.resume(throwing: ProviderError("Plex sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PresentationAnchorResolver.current()
    }
}

// MARK: - Decodable payloads

/// plex.tv PIN — `authToken` is null until the account link completes.
private struct PlexPin: Decodable, Sendable {
    let id: Int
    let code: String
    let authToken: String?
}

/// plex.tv resource (a linked server/player). `provides` names its roles; a music
/// server includes "server". `accessToken` authorizes calls to that server.
private struct PlexResource: Decodable, Sendable {
    let provides: String?
    let accessToken: String?
    let connections: [PlexConnection]?
}

private struct PlexConnection: Decodable, Sendable {
    let uri: String?
    let local: Bool?
    let relay: Bool?
    let accessToken: String?
}

// Plex Media Server responses wrap everything in a capitalized `MediaContainer`.

private struct SectionsResponse: Decodable, Sendable {
    let mediaContainer: SectionsContainer
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

private struct SectionsContainer: Decodable, Sendable {
    let directory: [PlexDirectory]?
    enum CodingKeys: String, CodingKey { case directory = "Directory" }
}

private struct PlexDirectory: Decodable, Sendable {
    let key: String?
    let type: String?
    let title: String?
}

private struct MetadataResponse: Decodable, Sendable {
    let mediaContainer: MetadataContainer
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

private struct MetadataContainer: Decodable, Sendable {
    let metadata: [PlexMetadata]?
    enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
}

private struct PlexMetadata: Decodable, Sendable {
    let ratingKey: String?
    let title: String?
    let grandparentTitle: String?
    let grandparentRatingKey: String?
    let parentTitle: String?
    let thumb: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let composite: String?
    let duration: Int?
    let leafCount: Int?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, grandparentTitle, grandparentRatingKey
        case parentTitle, thumb, parentThumb, grandparentThumb, composite
        case duration, leafCount
        case media = "Media"
    }
}

private struct PlexMedia: Decodable, Sendable {
    let part: [PlexPart]?
    enum CodingKeys: String, CodingKey { case part = "Part" }
}

private struct PlexPart: Decodable, Sendable {
    let key: String?
}

private extension CharacterSet {
    /// Fully percent-encodes a URL used as a query/fragment *value* (encodes `:` and
    /// `/` too), so `heartable://plex-linked` survives intact inside the auth URL.
    static let plexForwardAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
