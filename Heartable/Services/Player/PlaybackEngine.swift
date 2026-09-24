import Foundation
import Observation

/// Applies the active skip-version to whatever's playing: when the position
/// enters a skip region it seeks past it (and skips to the end of the track if
/// the region runs to the end). Reloads the active version on track change and
/// on any SkipStore write. Ported from the RN usePlaybackEngine.
@MainActor
@Observable
final class PlaybackEngine {
    private static let lookaheadMs = 700
    private static let settleMs = 2200

    private var loadedURI: String?
    private var loadedRevision = -1
    private var regions: [SkipRegion] = []
    private var lastSeekAt: Date = .distantPast

    /// Called from the app shell tick alongside NowPlayingSync.
    func apply(now: PlayerStore.Now?, skips: SkipStore, player: PlayerStore) async {
        guard let now else { regions = []; loadedURI = nil; return }

        // (Re)load the active version when the track or skip data changes.
        if now.uri != loadedURI || skips.revision != loadedRevision {
            loadedURI = now.uri
            loadedRevision = skips.revision
            regions = (await skips.active(for: now.uri))?.skipRegions ?? []
        }

        guard now.isPlaying, !regions.isEmpty else { return }
        // Don't re-fire a seek we just issued (3s polls can read a stale position).
        guard Date().timeIntervalSince(lastSeekAt) * 1000 > Double(Self.settleMs) else { return }

        let pos = now.positionMs + Self.lookaheadMs
        if let region = regions.first(where: { pos >= $0.start && pos < $0.end }) {
            lastSeekAt = Date()
            if now.durationMs > 0, region.end >= now.durationMs - 1000 {
                await player.next()           // region runs to the end → next track
            } else {
                await player.seek(toMs: region.end)
            }
        }
    }
}
