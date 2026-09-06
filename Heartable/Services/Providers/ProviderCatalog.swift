import SwiftUI

enum ProviderStatus: Sendable {
    case live          // adapter wired + usable
    case stubbed       // adapter exists but inactive
    case comingSoon    // documented, not wired (needs creds/server/no API)
}

enum ProviderSection: String, CaseIterable, Sendable {
    case library = "Music providers"
    case history = "Listening history"
    case discovery = "Search"
    case comingSoon = "Coming soon"
}

/// Which unified features a service's API actually exposes. Differs per service
/// (e.g. Audius/Deezer have no user login, so no personal liked/playlists), so the
/// Music Services screen shows a lit/greyed icon per capability.
struct ProviderCapabilities: OptionSet, Sendable {
    let rawValue: Int
    static let top       = ProviderCapabilities(rawValue: 1 << 0)
    static let liked     = ProviderCapabilities(rawValue: 1 << 1)
    static let playlists = ProviderCapabilities(rawValue: 1 << 2)
    static let search    = ProviderCapabilities(rawValue: 1 << 3)
    static let playback  = ProviderCapabilities(rawValue: 1 << 4)

    /// Display order + legend metadata for the capability key.
    static let ordered: [(cap: ProviderCapabilities, icon: String, label: String)] = [
        (.top,       "chart.line.uptrend.xyaxis", "Top"),
        (.liked,     "heart.fill",                "Liked"),
        (.playlists, "music.note.list",           "Playlists"),
        (.search,    "magnifyingglass",           "Search"),
        (.playback,  "play.fill",                 "Playback"),
    ]
}

/// Everything Heartable knows about — live and not. Drives MusicServices +
/// onboarding. Ported from the RN `providers/catalog.ts` with honest status.
struct ProviderCatalogEntry: Identifiable, Sendable {
    let id: ProviderID
    let label: String
    let brandColor: Color
    let sfSymbol: String
    let blurb: String
    let status: ProviderStatus
    let capabilities: ProviderCapabilities
    let setupSteps: [String]
    let setupURL: URL?
    let playbackTier: ProviderPlayback.Tier
    let usesLocalAudioEngine: Bool
    let makeProvider: @Sendable () -> any MusicProvider

    var isPublicSearch: Bool {
        [.audius, .deezer, .internetArchive, .wsum].contains(id)
    }

    var requiresAccountConnection: Bool { status == .live && !isPublicSearch }

    /// Presentation reflects the implemented integration, not every feature the
    /// upstream service might offer. Public catalogs are not account connections.
    var section: ProviderSection {
        guard status == .live else { return .comingSoon }
        if id == .lastfm { return .history }
        if capabilities.contains(.playlists) || capabilities.contains(.liked) { return .library }
        return .discovery
    }

    init(_ id: ProviderID, _ label: String, _ color: UInt32, _ symbol: String,
         _ blurb: String, _ status: ProviderStatus,
         caps: ProviderCapabilities = [],
         steps: [String] = [], url: String? = nil,
         playbackTier: ProviderPlayback.Tier = .none,
         usesLocalAudioEngine: Bool = false,
         adapter: (@Sendable () -> any MusicProvider)? = nil) {
        self.id = id
        self.label = label
        self.brandColor = Color(hex: color)
        self.sfSymbol = symbol
        self.blurb = blurb
        self.status = status
        self.capabilities = caps
        self.setupSteps = steps
        self.setupURL = url.flatMap(URL.init(string:))
        self.playbackTier = playbackTier
        self.usesLocalAudioEngine = usesLocalAudioEngine
        self.makeProvider = adapter ?? { StubProvider(id: id) }
    }
}

enum ProviderCatalog {
    static let all: [ProviderCatalogEntry] = [
        .init(.apple, "Apple Music", 0xfa2d48, "music.note.list",
              "Your library, playlists, search, and playback through native MusicKit.", .live,
              caps: [.liked, .playlists, .search, .playback],
              steps: ["Enable MusicKit under the Heartable App ID’s App Services.",
                      "Authorize Music access on this device."],
              url: "https://developer.apple.com/musickit/",
              playbackTier: .full,
              adapter: { AppleMusicProvider() }),
        .init(.spotify, "Spotify", 0x1DB954, "music.note",
              "Top tracks, liked songs, playlists, playback control.", .live,
              caps: [.top, .liked, .playlists, .search, .playback],
              playbackTier: .full,
              adapter: { SpotifyProvider() }),
        .init(.audius, "Audius", 0x7e1bcc, "infinity",
              "Open music network. Full tracks play right in the app.", .live,
              caps: [.search, .playback],
              url: "https://docs.audius.org/api/",
              playbackTier: .full,
              usesLocalAudioEngine: true,
              adapter: { AudiusProvider() }),
        .init(.deezer, "Deezer", 0xa238ff, "headphones",
              "Public search with 30-second previews in-app.", .live,
              caps: [.search, .playback],
              url: "https://developers.deezer.com/",
              playbackTier: .preview,
              usesLocalAudioEngine: true,
              adapter: { DeezerProvider() }),
        .init(.internetArchive, "Internet Archive", 0x000000, "building.columns.fill",
              "Open audio archive. Full items play right in the app.", .live,
              caps: [.search, .playback],
              url: "https://archive.org/details/audio",
              playbackTier: .full,
              usesLocalAudioEngine: true,
              adapter: { InternetArchiveProvider() }),
        .init(.wsum, "WSUM", 0xc62836, "dot.radiowaves.left.and.right",
              "Madison’s student radio: 91.7 FM, Freeflow, and Sports, streamed in-app.", .live,
              caps: [.search, .playback],
              url: "https://wsum.org/",
              playbackTier: .full,
              usesLocalAudioEngine: true,
              adapter: { WSUMProvider() }),
        // Last.fm lights up the moment LASTFM_API_KEY lands in Secrets; until
        // then it's honestly "needs credentials". The username is typed in-app.
        .init(.lastfm, "Last.fm", 0xd51007, "chart.bar.fill",
              "All-time top and loved tracks from your scrobbles.",
              AppConfig.lastfmAPIKey != nil ? .live : .stubbed,
              caps: [.top, .liked, .search],
              steps: ["last.fm/api/account/create › grab a free key.",
                      "Add LASTFM_API_KEY to Secrets.xcconfig and rebuild.",
                      "Tap Connect and enter your Last.fm username."],
              url: "https://www.last.fm/api/account/create",
              adapter: { LastfmProvider() }),
        // Unimplemented services are collected in Coming soon, not represented
        // by nonfunctional connection buttons. Plex/Jellyfin below are live.
        .init(.soundcloud, "SoundCloud", 0xff5500, "cloud.fill",
              "Account connection, likes, playlists, and playback are not integrated yet.", .comingSoon,
              steps: ["Register a SoundCloud API application, then implement and verify OAuth and playback."],
              url: "https://developers.soundcloud.com/"),
        .init(.tidal, "Tidal", 0x000000, "water.waves",
              "Hi-fi catalog. Needs a registered app + review.", .comingSoon,
              steps: ["developer.tidal.com › create an app (PKCE)."],
              url: "https://developer.tidal.com/"),
        .init(.plex, "Plex", 0xe5a00d, "server.rack",
              "Self-hosted music from your own Plex server. Full tracks play right in the app.", .live,
              caps: [.top, .playlists, .search, .playback],
              steps: ["Tap Connect, sign in to your Plex account, and approve the device.",
                      "Heartable finds your Plex Media Server and reads your music library."],
              url: "https://www.plex.tv/",
              playbackTier: .full,
              usesLocalAudioEngine: true,
              adapter: { PlexProvider() }),
        .init(.jellyfin, "Jellyfin", 0xaa5cc3, "server.rack",
              "Your own Jellyfin server. Full tracks play right in the app.", .live,
              caps: [.top, .liked, .playlists, .search, .playback],
              steps: ["Tap Connect and enter your server address, username, and password.",
                      "Heartable reads your music library and streams straight from your server."],
              url: "https://jellyfin.org/",
              playbackTier: .full,
              usesLocalAudioEngine: true,
              adapter: { JellyfinProvider() }),
        .init(.qobuz, "Qobuz", 0x0085d3, "music.quarternote.3",
              "Qobuz account and playback integration is not implemented yet.", .comingSoon),
        .init(.youtubeMusic, "YouTube Music", 0xFF0000, "play.rectangle.fill",
              "YouTube Music account and playback integration is not implemented yet.", .comingSoon),
        .init(.amazonMusic, "Amazon Music", 0x00A8E1, "cart.fill",
              "Amazon Music integration is not implemented; developer access requires approval.", .comingSoon),
        .init(.bandcamp, "Bandcamp", 0x1da0c3, "opticaldisc.fill",
              "Collection streaming and playlists through Bandcamp’s Subsonic beta are not integrated yet.", .comingSoon),
        .init(.pandora, "Pandora", 0x00a0ee, "radio.fill",
              "Pandora integration is not implemented; partner access is required.", .comingSoon),
    ]

    static func entry(_ id: ProviderID) -> ProviderCatalogEntry? {
        all.first { $0.id == id }
    }

    static var publicSearchIDs: [ProviderID] {
        all.filter { $0.status == .live && $0.isPublicSearch }.map(\.id)
    }

    static func entries(in section: ProviderSection) -> [ProviderCatalogEntry] {
        all.filter { $0.section == section }
    }
}
