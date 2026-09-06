import Foundation

/// Curated public station endpoints from WSUM's official web player, verified
/// 2026-09-05. Stored IDs are stable; playback never trusts a shared track URL.
/// WSUM is a public search source, not an account connection.
enum FeaturedRadioStations {
    struct Station: Sendable {
        let id: String
        let name: String
        let stream: URL

        var track: UnifiedTrack {
            UnifiedTrack(key: trackKey(.wsum, id), providerID: .wsum,
                         providerTrackID: id, uri: "wsum:track:\(id)", name: name,
                         artists: [.init(id: "wsum", name: "WSUM · Madison, Wisconsin")],
                         album: nil,
                         albumArt: URL(string: "https://wsum.org/wp-content/frontity/build/static/images/WSUM%20Placeholder%20Logo%20Colored-7f2b339e6e2154611252cadf6ffd3d1f.png"),
                         durationMs: 0)
        }
    }

    static let all: [Station] = [
        .init(id: "wsum-fm", name: "WSUM 91.7 FM", stream: URL(string: "https://ice23.securenetsystems.net/WSUMFM")!),
        .init(id: "wsum-freeflow", name: "WSUM Freeflow", stream: URL(string: "https://ice23.securenetsystems.net/FREEFLOW")!),
        .init(id: "wsum-sports", name: "WSUM Sports", stream: URL(string: "https://ice64.securenetsystems.net/WSUMSPORTS")!)
    ]

    static func station(id: String) -> Station? { all.first { $0.id == id } }

    static func search(_ query: String) -> [UnifiedTrack] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return all.filter { station in
            let text = "\(station.name) Madison Wisconsin radio".lowercased()
            return words.allSatisfy { text.contains($0) }
        }.map(\.track)
    }
}
