import Foundation

/// How fully a service can actually play a track. Used to route a unified track to
/// the best source: a song available on both Spotify (full) and Deezer (30s
/// preview) should play from Spotify by default, while a stats-only source
/// (Last.fm, ListenBrainz) can never be the playback target.
enum ProviderPlayback {
    enum Tier: Int, Sendable, Comparable {
        case none = 0       // stats/metadata only — cannot play here
        case preview = 1    // short preview only (e.g. Deezer 30s)
        case full = 2       // full-length in-app or native playback

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static func tier(for id: ProviderID) -> Tier {
        ProviderCatalog.entry(id)?.playbackTier ?? .none
    }

    static func isPlayable(_ id: ProviderID) -> Bool { tier(for: id) != .none }

    /// Short user-facing note for a source in the picker (no em-dashes).
    static func label(for id: ProviderID) -> String {
        switch tier(for: id) {
        case .full: return "Play in full"
        case .preview: return "30s preview"
        case .none: return "Stats only"
        }
    }
}
