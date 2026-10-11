import Foundation

/// How fully a service can actually play a track. Used to route a unified track to
/// the best source; a source without a playback tier (planned or retired
/// services) can never be the playback target.
enum ProviderPlayback {
    enum Tier: Int, Sendable, Comparable {
        case none = 0       // metadata only — cannot play here
        case full = 1       // full-length in-app or native playback

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static func tier(for id: ProviderID) -> Tier {
        ProviderCatalog.entry(id)?.playbackTier ?? .none
    }

    static func isPlayable(_ id: ProviderID) -> Bool { tier(for: id) != .none }

    static func isPlayable(_ track: UnifiedTrack) -> Bool {
        guard isPlayable(track.providerID), track.playbackUnavailableReason == nil else { return false }
        if track.providerID == .spotify {
            return !track.providerTrackID.isEmpty && track.uri.hasPrefix("spotify:track:")
                && !track.uri.dropFirst("spotify:track:".count).isEmpty
        }
        return true
    }
}
