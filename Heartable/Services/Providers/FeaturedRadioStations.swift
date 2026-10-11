import Foundation

/// Canonical station endpoints published by the broadcasters. Saved station IDs
/// stay stable; playback never trusts a stream URL embedded in a shared track.
enum FeaturedRadioStations {
    struct Station: Sendable {
        let id: String
        let name: String
        let location: String
        let stream: URL

        var providerID: ProviderID { id.hasPrefix("wsum-") ? .wsum : .radioBrowser }
        var artwork: URL? {
            providerID == .wsum ? URL(string: "https://wsum.org/wp-content/frontity/build/static/images/WSUM%20Placeholder%20Logo%20Colored-7f2b339e6e2154611252cadf6ffd3d1f.png") : nil
        }
        var track: UnifiedTrack {
            UnifiedTrack(key: trackKey(providerID, id), providerID: providerID,
                         providerTrackID: id, uri: "\(providerID.rawValue):track:\(id)", name: name,
                         artists: [.init(id: id, name: location)], album: nil,
                         albumArt: artwork, durationMs: 0)
        }
    }

    // Official sources verified 2026-09-23:
    // https://www.kexp.org/mobile/kexp-livestreams/
    // https://www.wfmu.org/audiostream.shtml
    // WSUM's official web player; existing IDs and streams are preserved.
    static let all: [Station] = [
        .init(id: "wsum-fm", name: "WSUM 91.7 FM", location: "Madison, Wisconsin", stream: URL(string: "https://ice23.securenetsystems.net/WSUMFM")!),
        .init(id: "wsum-freeflow", name: "WSUM Freeflow", location: "Madison, Wisconsin", stream: URL(string: "https://ice23.securenetsystems.net/FREEFLOW")!),
        .init(id: "wsum-sports", name: "WSUM Sports", location: "Madison, Wisconsin", stream: URL(string: "https://ice64.securenetsystems.net/WSUMSPORTS")!),
        .init(id: "kexp", name: "KEXP 90.3 FM", location: "Seattle, Washington", stream: URL(string: "https://kexp.streamguys1.com/kexp160.aac")!),
        .init(id: "wfmu", name: "WFMU 91.1 FM", location: "Jersey City, New Jersey", stream: URL(string: "https://stream0.wfmu.org/freeform-128k")!)
    ]

    static func station(id: String) -> Station? { all.first { $0.id == id } }

    static func matching(_ query: String) -> [Station] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        return all.filter { station in
            let text = "\(station.name) \(station.location) radio".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    static func search(_ query: String) -> [UnifiedTrack] { matching(query).map(\.track) }
}
