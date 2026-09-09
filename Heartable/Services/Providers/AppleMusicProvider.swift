import Foundation
import MusicKit

/// Apple Music via Apple's native **MusicKit** framework (no React Native bridge).
///
/// MusicKit handles its own developer token from the app's MusicKit entitlement
/// on the bundle id (`com.zlichtman.heartable`) — there is no client-side JWT to
/// sign. For authorization to ever return `.authorized`, the bundle id must:
///
///   1. developer.apple.com › Identifiers › Music IDs → register the app
///   2. developer.apple.com › Identifiers › App IDs → enable the MusicKit capability
///   3. Re-fetch the provisioning profile (Automatic Signing handles this;
///      team 28LJG7MXT3)
///
/// Until those are in place, `MusicAuthorization.request()` returns `.denied`
/// or `.restricted` and `connect()` surfaces a clear, user-facing message.
///
/// Behavior parity with the RN `apple.ts` adapter, but built on native MusicKit
/// request types instead of `@lomray/react-native-apple-music`.
struct AppleMusicProvider: MusicProvider {
    let id: ProviderID = .apple

    /// MusicKit authorization can't be revoked programmatically, so "disconnect"
    /// is a local override: once set, the app treats Apple Music as not connected
    /// even though the OS-level grant remains. Reconnecting just clears the flag.
    private static let disabledKey = "apple_music_disabled"
    static var isDisabled: Bool {
        // A newly signed-in Heartable account must explicitly pair MusicKit even
        // when iOS already authorized it for a different account on this device.
        get { AccountSessionStore.defaultBool(forKey: disabledKey, defaultValue: true) }
        set { AccountSessionStore.setDefault(newValue, forKey: disabledKey) }
    }

    // MARK: Connection

    /// Authorization is a static MusicKit property; no network call. Honors the
    /// local disconnect override so the user can turn Apple Music off in-app.
    func isConnected() async -> Bool {
        !Self.isDisabled && MusicAuthorization.currentStatus == .authorized
    }

    /// Prompts for Apple Music access. `request()` resolves immediately (without
    /// re-prompting) once a determination has been made, so it's safe to call
    /// repeatedly. Throws a user-facing message on anything but `.authorized`.
    func connect() async throws {
        Self.isDisabled = false   // clear any prior in-app disconnect
        let status = await MusicAuthorization.request()
        switch status {
        case .authorized:
            return
        case .denied:
            throw ProviderError(
                "Apple Music access was denied. Enable Apple Music access in Settings ▸ Privacy ▸ Media & Apple Music."
            )
        case .restricted:
            throw ProviderError(
                "Apple Music is restricted on this device (Screen Time or an MDM profile is blocking it)."
            )
        case .notDetermined:
            fallthrough
        @unknown default:
            throw ProviderError(
                "Apple Music couldn't authorize. Make sure you're signed into Apple Music on this device and try again."
            )
        }
    }

    /// MusicKit has no programmatic revoke, so we set a local disconnect flag (so
    /// the app stops treating Apple Music as connected) and stop the application
    /// player so audio doesn't keep playing. The OS grant stays; reconnect clears it.
    func disconnect() async {
        Self.isDisabled = true
        // NOTE: ApplicationMusicPlayer is @MainActor-isolated in MusicKit.
        await MainActor.run {
            ApplicationMusicPlayer.shared.stop()
        }
    }

    func restoreConnection(metadata: [String: String]) async {
        // MusicKit permission is device-owned, while the decision to include
        // Apple Music in Heartable belongs to the Heartable account.
        Self.isDisabled = false
    }

    /// Stops account-owned playback during sign-out/account switching without
    /// changing MusicKit authorization or this account's connection preference.
    @MainActor
    static func stopPlayback() {
        ApplicationMusicPlayer.shared.stop()
    }

    // MARK: Reads (never throw — return [] on not-authorized/failure)

    /// MusicKit does not expose a personal, time-windowed top-tracks ranking or
    /// per-track play counts. Recently played is only an ordered recency signal,
    /// while library songs and catalog charts are not listening stats. Returning
    /// no rows keeps all three from being presented as equivalent to Spotify's
    /// affinity ranking or Heartable's observed play counts.
    func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] {
        []
    }

    /// Apple Music's auto-generated library playlist for favorited songs. Excluded
    /// from `playlists()` and merged into `likedTracks()` so all favorites land in
    /// the single unified Liked list rather than surfacing as a stray playlist.
    private static let favoritesPlaylistName = "Favorite Songs"

    /// The user's library songs plus their "Favorite Songs" (the heart) merged in,
    /// deduped by unified key. "Liked" has no single MusicKit concept, so we union
    /// the saved library with the auto-created Favorites playlist.
    func likedTracks(limit: Int) async -> [UnifiedTrack] {
        guard MusicAuthorization.currentStatus == .authorized else { return [] }
        var librarySongs: [UnifiedTrack] = []
        do {
            var request = MusicLibraryRequest<Song>()
            // NOTE: sorting by libraryAddedDate (descending) surfaces the most
            // recently saved songs first; key path is verified MusicKit API.
            request.sort(by: \.libraryAddedDate, ascending: false)
            request.limit = limit
            let response = try await request.response()
            librarySongs = Array(response.items.prefix(limit)).map(Self.mapSong)
        } catch {
            // Keep going — Favorites alone is still useful.
        }

        let favorites = await Self.favoriteSongs()

        // Favorites first (they're the explicit "liked" signal), then the rest of
        // the library, deduped by unified key (`providerID:trackID`).
        var seen = Set<String>()
        var merged: [UnifiedTrack] = []
        for t in favorites + librarySongs where seen.insert(t.key).inserted {
            merged.append(t)
        }
        return merged
    }

    func playlists() async -> [UnifiedPlaylist] {
        guard MusicAuthorization.currentStatus == .authorized else { return [] }
        do {
            let pageSize = 100
            var offset = 0
            var playlists: [Playlist] = []
            while true {
                var request = MusicLibraryRequest<Playlist>()
                request.limit = pageSize
                request.offset = offset
                let page = Array(try await request.response().items)
                playlists.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += page.count
            }
            // Hide the auto-created "Favorite Songs" playlist — its tracks are
            // funneled into the unified Liked list instead (see likedTracks).
            return playlists
                .filter { !Self.isFavoritesPlaylist($0) }
                .map(Self.mapPlaylist)
        } catch {
            return []
        }
    }

    /// True when a library playlist is Apple Music's auto-created favorites list,
    /// matched case-insensitively by its name.
    private static func isFavoritesPlaylist(_ playlist: Playlist) -> Bool {
        playlist.name.compare(favoritesPlaylistName, options: .caseInsensitive) == .orderedSame
    }

    /// Loads the tracks of the "Favorite Songs" library playlist. Returns [] when
    /// it doesn't exist or can't load (never throws to the UI).
    private static func favoriteSongs() async -> [UnifiedTrack] {
        do {
            // Filter the library playlists by name, then load the matching one's
            // tracks relationship via `with([.tracks])`.
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.name, equalTo: favoritesPlaylistName)
            let response = try await request.response()
            guard let favorites = response.items.first(where: isFavoritesPlaylist) else {
                return []
            }
            let detailed = try await favorites.with([.tracks])
            guard let tracks = detailed.tracks else { return [] }
            return tracks.compactMap(mapTrack)
        } catch {
            return []
        }
    }

    func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] {
        guard MusicAuthorization.currentStatus == .authorized else { return [] }
        do {
            // Walk the complete library in pages. The previous default request
            // only searched the first page, so playlists after it could appear in
            // Library but always fail when opened.
            let pageSize = 100
            var offset = 0
            var match: Playlist?
            while match == nil {
                var request = MusicLibraryRequest<Playlist>()
                request.limit = pageSize
                request.offset = offset
                let page = Array(try await request.response().items)
                match = page.first { $0.id.rawValue == playlistID }
                if match != nil || page.count < pageSize { break }
                offset += page.count
            }
            guard let match else { return [] }

            let detailed = try await match.with([.tracks])
            guard var tracks = detailed.tracks else { return [] }
            while tracks.hasNextBatch,
                  let next = try await tracks.nextBatch(limit: 100) {
                tracks += next
            }
            // Playlist tracks are `Track` (an enum-like wrapper); pull the Song
            // payload where present.
            return tracks.compactMap(Self.mapTrack)
        } catch {
            return []
        }
    }

    func search(_ query: String) async -> [UnifiedTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if MusicAuthorization.currentStatus == .authorized {
            for attempt in 0..<2 {
                guard !Task.isCancelled else { return [] }
                if let mapped = try? await Self.catalogSearch(trimmed),
                   !mapped.isEmpty {
                    return mapped
                }
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }
        guard !Task.isCancelled else { return [] }
        // REST catalog search (developer token; works without MusicKit auth).
        return await AppleMusicAPI.shared.search(trimmed)
    }

    private static func catalogSearch(_ term: String) async throws -> [UnifiedTrack] {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = 25
        return try await request.response().songs.map(Self.mapSong)
    }

    // MARK: Playback (native ApplicationMusicPlayer)

    func play(_ track: UnifiedTrack) async throws {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ProviderError("Connect Apple Music first.")
        }
        let song = try await Self.resolveSong(for: track.providerTrackID)
        guard let song else {
            throw ProviderError("Apple Music couldn't find this track to play.")
        }
        do {
            // NOTE: ApplicationMusicPlayer is @MainActor-isolated. Setting the
            // queue from a Song and calling play() is the canonical MusicKit path.
            await MainActor.run {
                let player = ApplicationMusicPlayer.shared
                player.queue = ApplicationMusicPlayer.Queue(for: [song])
            }
            try await ApplicationMusicPlayer.shared.play()
        } catch {
            throw ProviderError("Apple Music couldn't start playback.")
        }
    }

    /// Resolves a playable `Song` from a provider track id. Library ids start
    /// with `l.`; everything else is a catalog id. We try the matching surface
    /// first and fall back to the other so a verbatim id from either source plays.
    static func resolveSong(for trackID: String) async throws -> Song? {
        let itemID = MusicItemID(trackID)

        if trackID.hasPrefix("l.") {
            // Library song: filter the library by id.
            // NOTE: MusicLibraryRequest supports `filter(matching:equalTo:)` on id.
            var request = MusicLibraryRequest<Song>()
            request.filter(matching: \.id, equalTo: itemID)
            if let song = try? await request.response().items.first {
                return song
            }
        }

        // Catalog song (or library lookup failed): resolve via the catalog.
        var catalog = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
        catalog.limit = 1
        if let song = try? await catalog.response().items.first {
            return song
        }

        // Last resort for a library id that didn't resolve above: scan the library.
        var fallback = MusicLibraryRequest<Song>()
        fallback.filter(matching: \.id, equalTo: itemID)
        return try? await fallback.response().items.first
    }

    // MARK: Mapping

    /// Maps a MusicKit `Song` into the unified model.
    static func mapSong(_ song: Song) -> UnifiedTrack {
        let rawID = song.id.rawValue
        let durationMs = Int((song.duration ?? 0) * 1000)
        return UnifiedTrack(
            key: trackKey(.apple, rawID),
            providerID: .apple,
            providerTrackID: rawID,
            // Verbatim id preserved — `l.`-prefixed (library) vs catalog ids let
            // `play()` branch to the right resolution surface.
            uri: "apple:song:\(rawID)",
            name: song.title,
            artists: [UnifiedArtist(id: song.artistName, name: song.artistName)],
            album: song.albumTitle,
            albumArt: song.artwork?.url(width: 600, height: 600),
            durationMs: durationMs
        )
    }

    /// Maps a playlist `Track` (the relationship element type) when it carries a Song.
    private static func mapTrack(_ track: Track) -> UnifiedTrack? {
        // NOTE: `Track` is an enum with `.song` / `.musicVideo` cases on iOS 26.
        // We only surface songs; map them through a synthesized UnifiedTrack so
        // we don't depend on a Song-only relationship type.
        switch track {
        case .song(let song):
            return mapSong(song)
        default:
            let rawID = track.id.rawValue
            return UnifiedTrack(
                key: trackKey(.apple, rawID),
                providerID: .apple,
                providerTrackID: rawID,
                uri: "apple:song:\(rawID)",
                name: track.title,
                artists: [UnifiedArtist(id: track.artistName, name: track.artistName)],
                album: track.albumTitle,
                albumArt: track.artwork?.url(width: 600, height: 600),
                durationMs: Int((track.duration ?? 0) * 1000)
            )
        }
    }

    /// Maps a MusicKit library `Playlist` into the unified model.
    static func mapPlaylist(_ playlist: Playlist) -> UnifiedPlaylist {
        UnifiedPlaylist(
            key: "\(ProviderID.apple.rawValue):\(playlist.id.rawValue)",
            providerID: .apple,
            playlistID: playlist.id.rawValue,
            name: playlist.name,
            // NOTE: `standardDescription` is the editorial description; fall back
            // to the curator name when absent. Verify property on iOS 26 SDK.
            description: playlist.standardDescription ?? playlist.curatorName,
            image: playlist.artwork?.url(width: 600, height: 600),
            // Best-effort: the tracks relationship is only populated after a
            // `with([.tracks])` load, so this is 0 in the un-detailed list view.
            trackCount: playlist.tracks?.count ?? 0,
            owner: playlist.curatorName
        )
    }
}
