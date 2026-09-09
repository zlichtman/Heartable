import Foundation

/// Chooses useful first-open content without overriding a deliberate selection.
/// This is screen-session state, not an installation-wide account preference.
struct TopTracksSelection: Equatable {
    private(set) var source: TopTracksSource?
    private(set) var explicitSource: TopTracksSource?

    mutating func select(_ source: TopTracksSource) {
        self.source = source
        explicitSource = source
    }

    mutating func resolve(
        availableSources: [TopTracksSource],
        populatedSources: Set<TopTracksSource>
    ) {
        let candidates = Self.preferredOrder(availableSources)
        if let explicitSource, candidates.contains(explicitSource) {
            source = explicitSource
            return
        }
        explicitSource = nil
        // Keep an already-useful automatic selection stable during refreshes.
        if let source, candidates.contains(source), populatedSources.contains(source) {
            return
        }
        source = candidates.first(where: populatedSources.contains)
            ?? candidates.first
            ?? .heartable
    }

    static func preferredOrder(_ sources: [TopTracksSource]) -> [TopTracksSource] {
        let available = Set(sources.filter(\.providesTopTracks))
        return ([TopTracksSource.spotify] + TopTracksSource.allCases.filter { $0 != .spotify })
            .filter(available.contains)
    }
}
