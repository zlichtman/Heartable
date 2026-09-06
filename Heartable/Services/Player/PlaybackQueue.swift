import Foundation

/// Occurrences, rather than URIs, are queue identities: a playlist may contain
/// the same song twice. Provider queues receive the actual selected order.
struct PlaybackQueue {
    struct Entry: Identifiable, Equatable {
        let id: Int
        let track: UnifiedTrack
    }
    private var original: [Entry] = []
    private(set) var entries: [Entry] = []
    private(set) var index = 0

    var current: UnifiedTrack? { entries.indices.contains(index) ? entries[index].track : nil }
    var hasNext: Bool { index + 1 < entries.count }
    var hasPrevious: Bool { index > 0 }
    var isAtProviderBoundary: Bool {
        hasNext && entries[index + 1].track.providerID != current?.providerID
    }
    var remaining: [UnifiedTrack] { entries.dropFirst(index).map(\.track) }

    init(tracks: [UnifiedTrack] = [], startingAt: Int? = nil,
         mode: ShuffleMode = .order, weights: [String: Int] = [:]) {
        original = tracks.enumerated().compactMap {
            ProviderPlayback.isPlayable($0.element.providerID) ? Entry(id: $0.offset, track: $0.element) : nil
        }
        let selected = startingAt.flatMap { position in original.first { $0.id == position } }
        if mode == .order {
            entries = original
            index = selected.flatMap { entries.firstIndex(of: $0) } ?? 0
        } else {
            entries = Self.ordered(original.filter { $0.id != selected?.id }, mode: mode, weights: weights)
            if let selected { entries.insert(selected, at: 0) }
        }
    }

    mutating func reorder(mode: ShuffleMode, weights: [String: Int]) {
        guard entries.indices.contains(index) else { return }
        let current = entries[index]
        let played = Array(entries.prefix(index))
        let playedIDs = Set(played.map(\.id) + [current.id])
        entries = played + [current] + Self.ordered(original.filter { !playedIDs.contains($0.id) },
                                                    mode: mode, weights: weights)
    }

    mutating func next() { if hasNext { index += 1 } }
    mutating func previous() { if hasPrevious { index -= 1 } }
    mutating func observe(uri: String, newOccurrence: Bool = false) {
        guard current?.uri != uri || newOccurrence,
              let match = entries.indices.dropFirst(index + 1).first(where: { entries[$0].track.uri == uri }) else { return }
        index = match
    }

    /// A native queue can contain only one service. Mixed queues switch adapters
    /// at the boundary while Heartable is active.
    var providerSegment: [UnifiedTrack] {
        guard let provider = current?.providerID else { return [] }
        return Array(remaining.prefix { $0.providerID == provider })
    }

    private static func ordered(_ entries: [Entry], mode: ShuffleMode, weights: [String: Int]) -> [Entry] {
        let keys = entries.map { String($0.id) }
        let keyed = Dictionary(uniqueKeysWithValues: entries.map { (String($0.id), $0) })
        let factors = Dictionary(uniqueKeysWithValues: entries.map { (String($0.id), weights[$0.track.uri] ?? 0) })
        return orderForPlayback(keys, mode: mode, weights: factors).compactMap { keyed[$0] }
    }
}
