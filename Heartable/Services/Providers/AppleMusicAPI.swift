import Foundation

/// Apple Music **REST** client (api.music.apple.com), the cross-platform path
/// alongside the on-device MusicKit provider. It authorizes catalog requests with
/// a developer token signed server-side by the `apple-music-token` edge function
/// (the .p8 key never ships in the app), so this works without MusicKit being
/// authorized and would port to non-Apple platforms.
///
/// Scope: catalog reads (search, charts). Personal library + full playback still
/// require MusicKit on-device, so `AppleMusicProvider` keeps using native MusicKit
/// when authorized and falls back to this for catalog reads otherwise.
actor AppleMusicAPI {
    static let shared = AppleMusicAPI()

    private var cachedToken: String?
    private var tokenExpiry: Date?

    private let base = "https://api.music.apple.com/v1"

    /// Device storefront (region), defaulting to "us". The personal storefront
    /// needs a Music User Token; for catalog reads the region locale is enough.
    private var storefront: String {
        (Locale.current.region?.identifier ?? "US").lowercased()
    }

    // MARK: - Developer token

    /// A valid developer token, refreshing via the edge function when missing or
    /// within a day of expiry. Returns nil if the backend can't sign one (e.g. the
    /// Apple Music secrets aren't set), so callers degrade to empty results.
    private func developerToken() async -> String? {
        if let cachedToken, let tokenExpiry, tokenExpiry.timeIntervalSinceNow > 60 * 60 * 24 {
            return cachedToken
        }
        do {
            let (token, expiresAt) = try await BackendAPI.shared.appleMusicDeveloperToken()
            cachedToken = token
            tokenExpiry = expiresAt
            return token
        } catch {
            return nil
        }
    }

    // MARK: - Catalog reads

    /// Catalog song search.
    func search(_ query: String, limit: Int = 25) async -> [UnifiedTrack] {
        guard let url = Self.catalogSearchURL(
            base: base,
            storefront: storefront,
            query: query,
            limit: limit
        ) else { return [] }
        // search results live under results.songs.data
        return await songs(at: url, keyPath: ["results", "songs", "data"])
    }

    nonisolated static func catalogSearchURL(
        base: String = "https://api.music.apple.com/v1",
        storefront: String,
        query: String,
        limit: Int
    ) -> URL? {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty,
              var components = URLComponents(
                string: "\(base)/catalog/\(storefront)/search"
              ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "types", value: "songs"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 25)))),
            URLQueryItem(name: "term", value: term),
        ]
        return components.url
    }

    /// Catalog top songs (charts).
    func topSongs(limit: Int = 50) async -> [UnifiedTrack] {
        guard let url = URL(string: "\(base)/catalog/\(storefront)/charts?types=songs&limit=\(limit)")
        else { return [] }
        // charts come back under results.songs[0].data
        return await songs(at: url, keyPath: ["results", "songs", 0, "data"])
    }

    // MARK: - Fetch + map

    private func songs(at url: URL, keyPath: [Any]) async -> [UnifiedTrack] {
        guard let token = await developerToken() else { return [] }
        do {
            let (data, resp) = try await HTTPClient.send(
                url, headers: ["Authorization": "Bearer \(token)"]
            )
            guard (200..<300).contains(resp.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [] }
            guard let items = value(root, keyPath) as? [[String: Any]] else { return [] }
            return items.compactMap(Self.mapSong)
        } catch {
            return []
        }
    }

    /// Walks a mixed string/index key path through parsed JSON.
    private func value(_ root: Any, _ path: [Any]) -> Any? {
        var current: Any? = root
        for key in path {
            switch (current, key) {
            case let (dict as [String: Any], k as String): current = dict[k]
            case let (arr as [Any], i as Int): current = i < arr.count ? arr[i] : nil
            default: return nil
            }
        }
        return current
    }

    /// Maps an Apple Music catalog `songs` object into the unified model. Mirrors
    /// the native `AppleMusicProvider.mapSong` key scheme so dedup/playback line up.
    private static func mapSong(_ item: [String: Any]) -> UnifiedTrack? {
        guard let id = item["id"] as? String,
              let attrs = item["attributes"] as? [String: Any],
              let name = attrs["name"] as? String else { return nil }
        let artist = attrs["artistName"] as? String ?? ""
        let album = attrs["albumName"] as? String
        let durationMs = attrs["durationInMillis"] as? Int ?? 0
        var artURL: URL?
        if let artwork = attrs["artwork"] as? [String: Any],
           let template = artwork["url"] as? String {
            let sized = template
                .replacingOccurrences(of: "{w}", with: "600")
                .replacingOccurrences(of: "{h}", with: "600")
            artURL = URL(string: sized)
        }
        return UnifiedTrack(
            key: trackKey(.apple, id),
            providerID: .apple,
            providerTrackID: id,
            uri: "apple:song:\(id)",
            name: name,
            artists: [UnifiedArtist(id: artist, name: artist)],
            album: album,
            albumArt: artURL,
            durationMs: durationMs
        )
    }
}
