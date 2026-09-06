import Foundation

/// Thrown when Spotify Connect has no device to target. The Web API can't conjure
/// one. Typed so the in-app device chooser/fallback path is deterministic instead
/// of string-matching error messages. Ported from the RN `NoActiveDeviceError`.
struct NoActiveDeviceError: LocalizedError {
    var errorDescription: String? {
        "Spotify has not exposed a playback device yet."
    }
}

/// Keeps "there are no devices" distinct from auth, permission, rate-limit, and
/// transport failures. An empty array previously collapsed all of these states and
/// made Heartable present a chooser that could never contain an option.
enum SpotifyDeviceDiscovery: Sendable {
    case available([SpotifyDevice])
    case none
    case unavailable
    case unauthorized
    case forbidden
    case rateLimited(TimeInterval)
    case failed
}

/// Spotify Web API client, ported from the RN `src/spotify/api.ts`. All reads take
/// a bearer token; the player methods drive the user's active Spotify Connect
/// device. `play` retries on 404/502 by transferring to an available device, and
/// throws `NoActiveDeviceError` when no device exists anywhere.
enum SpotifyAPI {
    private static let base = "https://api.spotify.com/v1"

    // MARK: - User

    static func me(token: String) async throws -> SpotifyUser {
        try await getJSON("/me", token: token)
    }

    // MARK: - Top tracks

    static func topTracks(token: String, range: StatRange, limit: Int) async throws -> [SpotifyTrack] {
        // Spotify accepts at most 50 items for this endpoint. Passing the
        // repository's wider display limit used to turn a working stats request
        // into a 400 and an empty Spotify section.
        let limit = normalizedTopTracksLimit(limit)
        let page: Paged<SpotifyTrack> = try await getJSON(
            "/me/top/tracks?time_range=\(range.rawValue)&limit=\(limit)",
            token: token
        )
        return (page.items ?? []).filter { !$0.id.isEmpty }
    }

    static func normalizedTopTracksLimit(_ requested: Int) -> Int {
        min(max(requested, 1), 50)
    }

    // MARK: - Saved (liked) tracks

    /// Pages through `/me/tracks` (50/page) until `limit` is reached or there's no
    /// next page.
    static func savedTracks(token: String, limit: Int) async throws -> [SpotifyTrack] {
        var out: [SpotifyTrack] = []
        var offset = 0
        while out.count < limit {
            let pageSize = min(50, limit - out.count)
            let page: Paged<SavedTrack> = try await getJSON(
                "/me/tracks?limit=\(pageSize)&offset=\(offset)",
                token: token
            )
            let items = page.items ?? []
            out.append(contentsOf: items.compactMap(\.track))
            if page.next == nil || items.isEmpty { break }
            offset += items.count
        }
        return Array(out.prefix(limit))
    }

    // MARK: - Playlists

    /// Pages through `/me/playlists` up to `limit`.
    static func myPlaylists(token: String, limit: Int) async throws -> [SpotifyPlaylist] {
        var out: [SpotifyPlaylist] = []
        var offset = 0
        while out.count < limit {
            let pageSize = min(50, limit - out.count)
            let page: Paged<SpotifyPlaylist> = try await getJSON(
                "/me/playlists?limit=\(pageSize)&offset=\(offset)",
                token: token
            )
            let items = (page.items ?? []).filter { !$0.id.isEmpty && !$0.name.isEmpty }
            out.append(contentsOf: items)
            if page.next == nil || (page.items ?? []).isEmpty { break }
            offset += (page.items ?? []).count
        }
        return Array(out.prefix(limit))
    }

    /// Pages through every track in a playlist via `/playlists/{id}/items`.
    /// Spotify now 403s the older `/tracks` alias for some apps; `/items` is the
    /// supported endpoint (the playable nests under `item`, not `track`).
    static func playlistTracks(token: String, id: String) async throws -> [SpotifyTrack] {
        var out: [SpotifyTrack] = []
        var offset = 0
        while true {
            let page: Paged<PlaylistTrackItem> = try await getJSON(
                "/playlists/\(id)/items?limit=50&offset=\(offset)",
                token: token
            )
            let items = page.items ?? []
            out.append(contentsOf: items.compactMap(\.track).filter { !$0.id.isEmpty })
            if page.next == nil || items.isEmpty { break }
            offset += items.count
        }
        return out
    }

    // MARK: - Search

    static func search(token: String, q: String, limit: Int) async throws -> [SpotifyTrack] {
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let safeLimit = min(max(1, limit), 50)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        let result: SearchResult = try await getJSON(
            "/search?q=\(encoded)&type=track&limit=\(safeLimit)",
            token: token
        )
        return (result.tracks?.items ?? []).filter { !$0.id.isEmpty }
    }

    // MARK: - Artist images

    /// Real artist photos via `/artists?ids=` (track artist objects carry only an
    /// id + name, no image). Spotify caps `ids` at 50 per call, so this pages in
    /// chunks and returns id → best image URL. Best-effort: a failed chunk is
    /// skipped rather than thrown, so partial results still enrich the UI.
    static func artistImages(token: String, ids: [String]) async -> [String: URL] {
        let unique = Array(Set(ids.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }
        var out: [String: URL] = [:]
        var i = 0
        while i < unique.count {
            let chunk = Array(unique[i..<min(i + 50, unique.count)])
            i += 50
            let joined = chunk.joined(separator: ",")
            guard let result: ArtistsResponse = try? await getJSON("/artists?ids=\(joined)", token: token) else { continue }
            for a in result.artists ?? [] {
                guard let id = a.id, let urlStr = a.images?.first?.url, let url = URL(string: urlStr) else { continue }
                out[id] = url
            }
        }
        return out
    }

    // MARK: - Player

    static func recentlyPlayed(token: String) async throws -> [SpotifyRecentPlay] {
        let response: SpotifyRecentHistory = try await getJSON(
            "/me/player/recently-played?limit=50", token: token
        )
        return response.items ?? []
    }

    /// Result of a playback-state poll, including the rate-limit signal so the
    /// caller can back off instead of hammering the API into a longer 429.
    enum PlaybackPoll: Sendable {
        case state(PlaybackState)
        case idle                       // 204/202 or nothing playing
        case rateLimited(TimeInterval)  // 429 — wait this long before retrying
        case failed
    }

    static func pollPlayback(token: String) async -> PlaybackPoll {
        guard let url = URL(string: "\(base)/me/player") else { return .failed }
        do {
            let (data, resp) = try await HTTPClient.send(url, headers: bearer(token))
            switch resp.statusCode {
            case 204, 202:
                return .idle
            case 429:
                let retry = resp.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 5
                return .rateLimited(retry)
            case 200..<300:
                if let state = try? JSONDecoder().decode(PlaybackState.self, from: data) {
                    return .state(state)
                }
                return .idle
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    static func getDevices(token: String) async -> [SpotifyDevice] {
        if case .available(let devices) = await discoverDevices(token: token) {
            return devices
        }
        return []
    }

    static func discoverDevices(token: String) async -> SpotifyDeviceDiscovery {
        guard let url = URL(string: "\(base)/me/player/devices") else { return .failed }
        do {
            let (data, response) = try await HTTPClient.send(url, headers: bearer(token))
            switch response.statusCode {
            case 200..<300:
                guard let response = try? JSONDecoder().decode(DevicesResponse.self, from: data)
                else { return .failed }
                let returned = response.devices ?? []
                let devices = returned
                .filter { $0.id?.isEmpty == false && $0.isRestricted != true }
                .sorted {
                    if $0.isActive != $1.isActive { return $0.isActive }
                    return ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
                }
                if !devices.isEmpty { return .available(devices) }
                return returned.isEmpty ? .none : .unavailable
            case 401:
                return .unauthorized
            case 403:
                return .forbidden
            case 429:
                let retry = response.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? 5
                return .rateLimited(retry)
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Transfers playback to a device. A 404 is a real failure: treating it as a
    /// success made the picker checkmark a device that never received playback.
    @discardableResult
    static func transferPlayback(token: String, deviceId: String, play: Bool) async -> Bool {
        guard let url = URL(string: "\(base)/me/player") else { return false }
        let body = try? JSONSerialization.data(withJSONObject: ["device_ids": [deviceId], "play": play])
        do {
            let (_, resp) = try await HTTPClient.send(
                url,
                method: "PUT",
                headers: bearer(token).merging(["Content-Type": "application/json"]) { _, new in new },
                body: body
            )
            return (200..<300).contains(resp.statusCode)
        } catch {
            return false
        }
    }

    /// Start/resume playback. Retries and, on 404/502 (no active device), picks a
    /// device, transfers to it, and retries. Throws `NoActiveDeviceError` when no
    /// Connect device exists, or a user-facing `ProviderError` on other failures.
    @discardableResult
    static func play(
        token: String,
        uris: [String]? = nil,
        contextUri: String? = nil,
        deviceId: String? = nil,
        positionMs: Int? = nil
    ) async throws -> String? {
        var body: [String: Any] = [:]
        if let uris { body["uris"] = uris }
        if let contextUri { body["context_uri"] = contextUri }
        if let positionMs { body["position_ms"] = max(0, positionMs) }
        let bodyData = body.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: body)

        var device = deviceId
        for attempt in 0..<4 {
            try Task.checkCancellation()
            let query = device.map { "?device_id=\($0)" } ?? ""
            guard let url = URL(string: "\(base)/me/player/play\(query)") else {
                throw ProviderError("Invalid Spotify playback URL.")
            }
            let (data, resp): (Data, HTTPURLResponse)
            do {
                (data, resp) = try await HTTPClient.send(
                    url,
                    method: "PUT",
                    headers: bearer(token).merging(["Content-Type": "application/json"]) { _, new in new },
                    body: bodyData
                )
            } catch {
                try Task.checkCancellation()
                throw ProviderError("Couldn't reach Spotify playback.")
            }

            if (200..<300).contains(resp.statusCode) || resp.statusCode == 204 { return device }

            if (resp.statusCode == 404 || resp.statusCode == 502), attempt < 3 {
                if device == nil {
                    switch await discoverDevices(token: token) {
                    case .available(let devices):
                        device = devices.first(where: { $0.isActive })?.id
                            ?? devices.first?.id
                    case .none:
                        throw NoActiveDeviceError()
                    case .unavailable:
                        throw ProviderError(
                            "Spotify found devices, but none can accept playback."
                        )
                    case .unauthorized:
                        throw ProviderError("Session expired. Reconnect Spotify.")
                    case .forbidden:
                        throw ProviderError(
                            "Spotify did not permit Connect control for this account."
                        )
                    case .rateLimited:
                        throw ProviderError(
                            "Spotify is checking devices too often. Try again in a moment."
                        )
                    case .failed:
                        throw ProviderError(
                            "Couldn't check Spotify devices. Check your connection and try again."
                        )
                    }
                }
                if let device {
                    let transferred = await transferPlayback(
                        token: token,
                        deviceId: device,
                        play: false
                    )
                    guard transferred else {
                        throw ProviderError("Spotify couldn't switch to that device.")
                    }
                }
                try await Task.sleep(nanoseconds: UInt64(700_000_000 * (attempt + 1)))
                continue
            }

            throw ProviderError(parsePlayError(status: resp.statusCode, data: data))
        }
        // Exhausted retries without ever landing a device.
        throw NoActiveDeviceError()
    }

    // MARK: - Internals

    private static func bearer(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)"]
    }

    private static func getJSON<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: "\(base)\(path)") else {
            throw ProviderError("Invalid Spotify URL: \(path)")
        }
        let (data, resp) = try await HTTPClient.send(url, headers: bearer(token))
        guard (200..<300).contains(resp.statusCode) else {
            if resp.statusCode == 401 { throw ProviderError("Session expired. Please sign in again.") }
            throw ProviderError("Spotify API \(resp.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func parsePlayError(status: Int, data: Data) -> String {
        switch status {
        case 403: return "Spotify Premium is required to control playback."
        case 401: return "Session expired. Reconnect Spotify."
        case 404: return "No active Spotify device. Start playing on a device, then try again."
        default:
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any],
               let message = err["message"] as? String {
                return message
            }
            return "Playback error (\(status))"
        }
    }
}

// MARK: - Decodable payloads

struct SpotifyUser: Decodable, Sendable {
    let id: String
    let displayName: String?
    let email: String?
    let product: String?

    private enum CodingKeys: String, CodingKey {
        case id, email, product
        case displayName = "display_name"
    }
}

struct SpotifyImage: Decodable, Sendable {
    let url: String?
}

struct SpotifyArtist: Decodable, Sendable {
    let id: String?
    let name: String?
}

/// Full artist object from `/artists` (unlike the simplified `SpotifyArtist` on
/// tracks, this carries `images`). Used only to enrich artist art.
private struct ArtistsResponse: Decodable { let artists: [FullArtist]? }
private struct FullArtist: Decodable {
    let id: String?
    let name: String?
    let images: [SpotifyImage]?
}

struct SpotifyAlbum: Decodable, Sendable {
    let name: String?
    let images: [SpotifyImage]?
}

struct SpotifyTrack: Decodable, Sendable {
    let id: String
    let uri: String
    let name: String
    let artists: [SpotifyArtist]?
    let album: SpotifyAlbum?
    let durationMs: Int?

    private enum CodingKeys: String, CodingKey {
        case id, uri, name, artists, album
        case durationMs = "duration_ms"
    }

    // Tolerate missing ids/uris (some episode/local rows omit them) so a partial
    // payload doesn't fail the whole page decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        uri = (try? c.decode(String.self, forKey: .uri)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        artists = try? c.decode([SpotifyArtist].self, forKey: .artists)
        album = try? c.decode(SpotifyAlbum.self, forKey: .album)
        durationMs = try? c.decode(Int.self, forKey: .durationMs)
    }
}

struct SpotifyOwner: Decodable, Sendable {
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct SpotifyTrackCount: Decodable, Sendable {
    let total: Int?
}

struct SpotifyPlaylist: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]?
    let tracks: SpotifyTrackCount?
    let owner: SpotifyOwner?
    let snapshotID: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        description = try? c.decode(String.self, forKey: .description)
        images = try? c.decode([SpotifyImage].self, forKey: .images)
        tracks = try? c.decode(SpotifyTrackCount.self, forKey: .tracks)
        owner = try? c.decode(SpotifyOwner.self, forKey: .owner)
        snapshotID = try? c.decode(String.self, forKey: .snapshotID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, images, tracks, owner
        case snapshotID = "snapshot_id"
    }
}

struct SpotifyDevice: Decodable, Sendable {
    let id: String?
    let isActive: Bool
    let isRestricted: Bool?
    let name: String?
    let type: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, type
        case isActive = "is_active"
        case isRestricted = "is_restricted"
    }
}

struct PlaybackState: Decodable, Sendable {
    let isPlaying: Bool?
    let progressMs: Int?
    let device: SpotifyDevice?
    let item: SpotifyTrack?
    let shuffleState: Bool?
    let repeatState: String?

    private enum CodingKeys: String, CodingKey {
        case device, item
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case shuffleState = "shuffle_state"
        case repeatState = "repeat_state"
    }
}

private struct DevicesResponse: Decodable {
    let devices: [SpotifyDevice]?
}

private struct SearchResult: Decodable {
    let tracks: Paged<SpotifyTrack>?
}

private struct SavedTrack: Decodable {
    let track: SpotifyTrack?
}

/// A row from `/playlists/{id}/items` (or the legacy `/tracks`). The playable is
/// at `item` on the `/items` endpoint and at `track` on the old one — decode
/// whichever is present so either response shape yields a `track`.
private struct PlaylistTrackItem: Decodable {
    let track: SpotifyTrack?

    private enum CodingKeys: String, CodingKey { case item, track }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        track = try c.decodeIfPresent(SpotifyTrack.self, forKey: .item)
            ?? c.decodeIfPresent(SpotifyTrack.self, forKey: .track)
    }
}

private struct Paged<T: Decodable>: Decodable {
    let items: [T]?
    let next: String?
}
