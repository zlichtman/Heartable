import Foundation

/// The service-agnostic music model. Everything in the app speaks these types;
/// provider adapters normalize their native payloads into them. Ported from the
/// RN `Unified*` model.

struct UnifiedArtist: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
}

struct UnifiedTrack: Identifiable, Hashable, Sendable, Codable {
    /// Stable cross-app key: `"{providerID}:{providerTrackID}"`.
    let key: String
    let providerID: ProviderID
    /// Provider-native id (Spotify track id, Apple Music id, …).
    let providerTrackID: String
    /// Provider-native play handle (Spotify URI, `audius:track:123`, preview URL, …).
    let uri: String
    let name: String
    let artists: [UnifiedArtist]
    let album: String?
    let albumArt: URL?
    let durationMs: Int

    var id: String { key }
    var artistNames: String { artists.map(\.name).joined(separator: ", ") }

    /// MusicKit occasionally emits a partial refresh without artwork even though
    /// the same provider item had art in the last good snapshot. Preserve only
    /// that optional metadata; all authoritative song fields still come fresh.
    func preservingArtwork(from cached: UnifiedTrack?) -> UnifiedTrack {
        guard albumArt == nil, let cachedArt = cached?.albumArt else { return self }
        return UnifiedTrack(
            key: key,
            providerID: providerID,
            providerTrackID: providerTrackID,
            uri: uri,
            name: name,
            artists: artists,
            album: album,
            albumArt: cachedArt,
            durationMs: durationMs
        )
    }
}

struct UnifiedPlaylist: Identifiable, Hashable, Sendable, Codable {
    let key: String
    let providerID: ProviderID
    /// Provider-native playlist id.
    let playlistID: String
    let name: String
    let description: String?
    let image: URL?
    let trackCount: Int
    let owner: String?
    /// Creation time when known (mixtapes carry one; provider playlists don't).
    var createdAt: Date? = nil
    /// Provider-supplied content version when available (Spotify's snapshot id,
    /// for example). A changed value means the cached track list is stale even
    /// when the playlist still contains the same number of songs.
    var contentRevision: String? = nil

    var id: String { key }

    /// A Heartable mixtape rather than a connected-service playlist.
    var isMixtape: Bool { providerID == .heartable }

    func preservingArtwork(from cached: UnifiedPlaylist?) -> UnifiedPlaylist {
        guard image == nil, let cachedImage = cached?.image else { return self }
        return UnifiedPlaylist(
            key: key,
            providerID: providerID,
            playlistID: playlistID,
            name: name,
            description: description,
            image: cachedImage,
            trackCount: trackCount,
            owner: owner,
            createdAt: createdAt,
            contentRevision: contentRevision
        )
    }
}

/// `"{providerID}:{providerTrackID}"` — the identifier skip-edits + weights key on.
func trackKey(_ providerID: ProviderID, _ providerTrackID: String) -> String {
    "\(providerID.rawValue):\(providerTrackID)"
}
