import Foundation

/// Every music service Heartable knows about — live and stubbed. Raw values match
/// the RN ids so backend keys (`{providerID}:{trackID}`) stay compatible.
enum ProviderID: String, CaseIterable, Sendable, Codable, Identifiable {
    case spotify
    case apple
    case audius
    case deezer
    case lastfm = "last_fm"
    case soundcloud
    case tidal
    case youtubeMusic = "youtube_music"
    case amazonMusic = "amazon_music"
    case plex
    case jellyfin
    case bandcamp
    case qobuz
    case pandora
    case internetArchive = "internet_archive"
    case radioBrowser = "radio_browser"
    case listenbrainz
    case mixcloud
    /// Heartable itself — not a connectable service. Tags mixtapes so they can live
    /// in the unified library list alongside provider playlists.
    case heartable

    var id: String { rawValue }

    /// Sources whose audio runs through the in-app `LocalAudioEngine` (vs. the
    /// Spotify Connect device or MusicKit's player). Transport routing keys off
    /// this — add new in-app streaming providers here or seek/pause will
    /// misroute to Spotify.
    var playsViaLocalEngine: Bool {
        ProviderCatalog.entry(self)?.usesLocalAudioEngine ?? false
    }
}
