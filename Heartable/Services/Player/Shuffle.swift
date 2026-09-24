import Foundation

enum ShuffleMode: String, Sendable, CaseIterable {
    case order
    case shuffle

    var label: String { self == .order ? "In order" : "Shuffle" }
    var symbol: String { self == .order ? "list.number" : "shuffle" }
    var caption: String {
        self == .order ? "Plays songs in their original order" : "Plays songs in a random order"
    }
    var next: ShuffleMode { self == .order ? .shuffle : .order }

    /// Preserve shuffle intent when upgrading from the removed weighted mode.
    static func restored(from raw: String?) -> ShuffleMode {
        if raw == "weighted" { return .shuffle }
        return raw.flatMap(Self.init(rawValue:)) ?? .order
    }
}

func orderForPlayback(_ uris: [String], mode: ShuffleMode) -> [String] {
    mode == .order ? uris : uris.shuffled()
}
