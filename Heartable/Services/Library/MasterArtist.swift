import Foundation

/// An artist in the master library, deduped by normalized name across every
/// service. `providers` is the provenance (which services have a song by them);
/// `count` is how many distinct master tracks they appear on.
struct MasterArtist: Identifiable, Hashable, Sendable, Codable {
    /// Normalized-name key (matches `UnifiedTrackIdentity.normalizeArtist`).
    let id: String
    var name: String
    var providers: Set<ProviderID>
    var count: Int
    var artURL: URL?

    /// Aggregate artists from a set of master tracks. Each artist is counted once
    /// per master track (not once per source) so multi-service songs don't inflate
    /// the tally; provider provenance accumulates across all sources.
    static func aggregate(_ tracks: [MasterTrack]) -> [MasterArtist] {
        var map: [String: MasterArtist] = [:]
        let stableTracks = tracks.sorted { lhs, rhs in
            let leftRank = lhs.sources.map {
                ArtworkSourcePreference.rank($0.providerID)
            }.min() ?? Int.max
            let rightRank = rhs.sources.map {
                ArtworkSourcePreference.rank($0.providerID)
            }.min() ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.identity.key < rhs.identity.key
        }
        for track in stableTracks {
            var countedThisTrack: Set<String> = []
            let stableSources = track.sources.sorted {
                ArtworkSourcePreference.precedes($0.providerID, $1.providerID)
            }
            for source in stableSources {
                for artist in source.artists where !artist.name.isEmpty {
                    let key = UnifiedTrackIdentity.normalizeArtist(artist.name)
                    guard !key.isEmpty else { continue }
                    if var agg = map[key] {
                        agg.providers.insert(source.providerID)
                        if !countedThisTrack.contains(key) {
                            agg.count += 1
                            countedThisTrack.insert(key)
                        }
                        if agg.artURL == nil { agg.artURL = source.albumArt }
                        map[key] = agg
                    } else {
                        map[key] = MasterArtist(
                            id: key,
                            name: artist.name,
                            providers: [source.providerID],
                            count: 1,
                            artURL: source.albumArt
                        )
                        countedThisTrack.insert(key)
                    }
                }
            }
        }
        return map.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
