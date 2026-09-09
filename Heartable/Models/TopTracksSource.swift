import Foundation

/// The provenance of a personal top-tracks ranking.
///
/// Heartable is an observed play count from `play_log`. Spotify is Spotify's
/// own top-tracks ranking. Apple Music remains reserved for a future provider
/// implementation and is not currently selectable.
enum TopTracksSource: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case heartable
    case spotify
    case apple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heartable: "Heartable"
        case .spotify: "Spotify"
        case .apple: "Apple Music"
        }
    }

    var providerID: ProviderID {
        switch self {
        case .heartable: .heartable
        case .spotify: .spotify
        case .apple: .apple
        }
    }

    var providesTopTracks: Bool {
        switch self {
        case .heartable, .spotify: true
        case .apple: false
        }
    }

    static func selectableSources(
        connectedProviderIDs: Set<ProviderID>
    ) -> [TopTracksSource] {
        var sources: [TopTracksSource] = [.heartable]
        if connectedProviderIDs.contains(.spotify) {
            sources.append(.spotify)
        }
        return sources
    }
}
