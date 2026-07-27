import Foundation

/// Stable artwork precedence keeps an async provider race from changing the
/// cover picked for the same cross-service song between refreshes. Spotify art
/// is the most consistently available CDN source, Apple follows, and every
/// remaining provider has a deterministic lexical tie-break.
enum ArtworkSourcePreference {
    static func rank(_ provider: ProviderID) -> Int {
        switch provider {
        case .spotify: 0
        case .apple: 1
        default: 2
        }
    }

    static func precedes(_ lhs: ProviderID, _ rhs: ProviderID) -> Bool {
        let leftRank = rank(lhs)
        let rightRank = rank(rhs)
        if leftRank != rightRank { return leftRank < rightRank }
        return lhs.rawValue < rhs.rawValue
    }
}

/// A single song in the master library, deduped across every service that serves
/// it. It carries its cross-service `identity` and the full list of provider
/// `sources` (each an original `UnifiedTrack` with that provider's native id and
/// play handle) so playback can route to the best available service and the user
/// can pick a specific one.
struct MasterTrack: Identifiable, Hashable, Sendable, Codable {
    let identity: UnifiedTrackIdentity
    /// One original `UnifiedTrack` per owning provider (deduped by providerID).
    private(set) var sources: [UnifiedTrack]

    var id: String { identity.key }

    init(identity: UnifiedTrackIdentity, sources: [UnifiedTrack]) {
        self.identity = identity
        self.sources = sources
    }

    // MARK: - Provenance

    /// Providers that can serve this song, in the order they were added.
    var providers: [ProviderID] { sources.map(\.providerID) }
    var providerSet: Set<ProviderID> { Set(providers) }

    func source(for provider: ProviderID) -> UnifiedTrack? {
        sources.first { $0.providerID == provider }
    }

    /// True if at least one source can actually play (full or preview).
    var isPlayable: Bool { sources.contains { ProviderPlayback.isPlayable($0.providerID) } }

    // MARK: - Display (richest source wins)

    /// The most metadata-complete source, used for the row's title/art.
    var display: UnifiedTrack {
        sources.sorted { lhs, rhs in
            let leftRichness = Self.richness(lhs)
            let rightRichness = Self.richness(rhs)
            if leftRichness != rightRichness {
                return leftRichness > rightRichness
            }
            if lhs.providerID != rhs.providerID {
                return ArtworkSourcePreference.precedes(
                    lhs.providerID,
                    rhs.providerID
                )
            }
            return lhs.key < rhs.key
        }.first ?? sources[0]
    }
    var title: String { display.name }
    var artistNames: String { display.artistNames }
    var albumArt: URL? {
        sources
            .filter { $0.albumArt != nil }
            .sorted { lhs, rhs in
                if lhs.providerID != rhs.providerID {
                    return ArtworkSourcePreference.precedes(
                        lhs.providerID,
                        rhs.providerID
                    )
                }
                return lhs.key < rhs.key
            }
            .first?
            .albumArt
    }
    /// Longest known duration across sources (0 if none report one).
    var durationMs: Int { sources.map(\.durationMs).max() ?? 0 }

    private static func richness(_ t: UnifiedTrack) -> Int {
        (t.albumArt != nil ? 2 : 0) + (t.durationMs > 0 ? 1 : 0) + t.artists.count
    }

    // MARK: - Routing

    /// Best `UnifiedTrack` to hand the player: full-playback services first, then
    /// preview, then by the caller's priority order (falls back to none for a
    /// stats-only track). `order` is the user's provider priority (catalog order
    /// if unspecified).
    func bestPlaybackSource(order: [ProviderID] = []) -> UnifiedTrack? {
        sources
            .filter { ProviderPlayback.isPlayable($0.providerID) }
            .min { lhs, rhs in
                let lt = ProviderPlayback.tier(for: lhs.providerID)
                let rt = ProviderPlayback.tier(for: rhs.providerID)
                if lt != rt { return lt > rt }                 // higher tier first
                let li = order.firstIndex(of: lhs.providerID) ?? Int.max
                let ri = order.firstIndex(of: rhs.providerID) ?? Int.max
                return li < ri                                 // earlier priority first
            }
    }

    /// Playable sources ordered for the "Play from" picker (best first).
    func playableSources(order: [ProviderID] = []) -> [UnifiedTrack] {
        sources
            .filter { ProviderPlayback.isPlayable($0.providerID) }
            .sorted { lhs, rhs in
                let lt = ProviderPlayback.tier(for: lhs.providerID)
                let rt = ProviderPlayback.tier(for: rhs.providerID)
                if lt != rt { return lt > rt }
                let li = order.firstIndex(of: lhs.providerID) ?? Int.max
                let ri = order.firstIndex(of: rhs.providerID) ?? Int.max
                return li < ri
            }
    }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || artistNames.localizedCaseInsensitiveContains(query)
    }

    // MARK: - Building

    /// Merge/insert one provider track into an identity-keyed accumulator, keeping
    /// the richer source when the same provider already contributed one.
    static func insert(_ track: UnifiedTrack, into dict: inout [String: MasterTrack]) {
        let identity = UnifiedTrackIdentity.make(
            title: track.name,
            artist: track.artists.first?.name ?? ""
        )
        if var existing = dict[identity.key] {
            if let i = existing.sources.firstIndex(where: { $0.providerID == track.providerID }) {
                if richness(track) > richness(existing.sources[i]) {
                    existing.sources[i] = track
                }
            } else {
                existing.sources.append(track)
            }
            dict[identity.key] = existing
        } else {
            dict[identity.key] = MasterTrack(identity: identity, sources: [track])
        }
    }

    /// Group a flat list of provider tracks into deduped master tracks.
    static func group(_ tracks: [UnifiedTrack]) -> [MasterTrack] {
        var dict: [String: MasterTrack] = [:]
        for t in tracks { insert(t, into: &dict) }
        return Array(dict.values)
    }
}
