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
        case .weighted: "Plays your boosted songs more often"
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
        var pool = uris
        var result: [String] = []
        result.reserveCapacity(pool.count)
        while !pool.isEmpty {
            let factors = pool.map { uri -> Double in
                max(0.05, 1 + Double(weights[uri] ?? 0) / 10)
            }
            let total = factors.reduce(0, +)
            var roll = Double.random(in: 0..<total)
            var idx = 0
            for (i, f) in factors.enumerated() {
                roll -= f
                if roll <= 0 { idx = i; break }
            }
            result.append(pool.remove(at: idx))
        }
        return result
    }
}
