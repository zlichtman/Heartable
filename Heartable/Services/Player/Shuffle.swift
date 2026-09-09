import Foundation

enum ShuffleMode: String, Sendable, CaseIterable {
    case order      // play in order
    case shuffle    // uniform random
    case weighted   // weighted by per-song boost/downvote

    var label: String {
        switch self {
        case .order: "In order"
        case .shuffle: "Shuffle"
        case .weighted: "Weighted"
        }
    }
    var symbol: String {
        switch self {
        case .order: "list.number"
        case .shuffle: "shuffle"
        case .weighted: "slider.horizontal.3"
        }
    }

    /// One-line, plain-language explanation of what the mode does. Surfaced under
    /// the mode picker so weighted shuffle in particular is self-explanatory.
    var caption: String {
        switch self {
        case .order: "Plays songs in their original order"
        case .shuffle: "Plays songs in a random order"
        case .weighted: "Plays boosted songs earlier in the queue"
        }
    }

    /// The next mode in the order -> shuffle -> weighted -> order cycle. Lets a
    /// control offer a single tap-to-advance affordance in addition to the menu.
    var next: ShuffleMode {
        switch self {
        case .order: .shuffle
        case .shuffle: .weighted
        case .weighted: .order
        }
    }
}

/// Order a set of track uris for playback. Weighted draws without replacement
/// using the RN formula: weight in [-100, 100] → factor max(0.05, 1 + w/10).
/// Ported from the RN `orderForPlayback`.
func orderForPlayback(_ uris: [String], mode: ShuffleMode, weights: [String: Int]) -> [String] {
    switch mode {
    case .order:
        return uris
    case .shuffle:
        return uris.shuffled()
    case .weighted:
        // Exponential races implement weighted sampling without replacement in
        // O(n log n), avoiding repeated whole-library scans on the main thread.
        return uris.map { uri in
            let factor = max(0.05, 1 + Double(weights[uri] ?? 0) / 10)
            let priority = -log(Double.random(in: Double.leastNonzeroMagnitude..<1)) / factor
            return (uri, priority)
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
