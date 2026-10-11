import Foundation

/// One saved occurrence of a song. The collection is part of its identity so a
/// song removed from one playlist but retained in another is still visible in a
/// comparison.
struct BackupInventoryItem: Identifiable, Equatable, Sendable {
    let uri: String
    let name: String?
    let artist: String?
    let album: String?
    let artworkURL: String?
    let collection: String
    let position: Int
    var collectionID: String? = nil

    var id: String { "\(comparisonKey)#\(position)" }

    var comparisonKey: String {
        if let collectionID, !collectionID.isEmpty {
            return "\(uri)|id:\(collectionID)"
        }
        return legacyComparisonKey
    }

    var legacyComparisonKey: String {
        let normalizedCollection = collection
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(uri)|\(normalizedCollection)"
    }

    var providerID: ProviderID? {
        ProviderID(rawValue: String(uri.prefix { $0 != ":" }))
    }
}

struct BackupSnapshotDifference: Equatable, Sendable {
    let added: [BackupInventoryItem]
    let removed: [BackupInventoryItem]
}

enum BackupSnapshotDiffer {
    /// Multiset comparison preserves duplicate occurrences while matching on the
    /// stable provider URI plus collection ID, falling back to legacy names.
    static func difference(
        current: [BackupInventoryItem],
        previous: [BackupInventoryItem]
    ) -> BackupSnapshotDifference {
        var buckets = Dictionary(grouping: previous.indices, by: { previous[$0].comparisonKey })
            .mapValues { Array($0.reversed()) }
        var matchedCurrent = Set<Int>()
        var matchedPrevious = Set<Int>()
        for index in current.indices {
            if let match = buckets[current[index].comparisonKey]?.popLast() {
                matchedCurrent.insert(index)
                matchedPrevious.insert(match)
            }
        }
        // Older snapshots omit provider playlist IDs. Match those legacy rows by
        // name, but never merge two known, distinct playlists.
        var legacy = Dictionary(grouping: previous.indices.filter { !matchedPrevious.contains($0) },
                                by: { previous[$0].legacyComparisonKey })
        for index in current.indices where !matchedCurrent.contains(index) {
            let item = current[index]
            guard let candidates = legacy[item.legacyComparisonKey],
                  let offset = candidates.firstIndex(where: {
                      item.collectionID == nil || previous[$0].collectionID == nil
                  }) else { continue }
            let match = candidates[offset]
            legacy[item.legacyComparisonKey]?.remove(at: offset)
            matchedCurrent.insert(index)
            matchedPrevious.insert(match)
        }
        return BackupSnapshotDifference(
            added: current.indices.filter { !matchedCurrent.contains($0) }.map { current[$0] },
            removed: previous.indices.filter { !matchedPrevious.contains($0) }.map { previous[$0] }
        )
    }
}

struct BackupComparisonScope {
    let sharedProviders: Set<ProviderID>
    let excludedProviders: Set<ProviderID>

    init(current: [BackupInventoryItem], previous: [BackupInventoryItem]) {
        let currentProviders = Set(current.compactMap(\.providerID))
        let previousProviders = Set(previous.compactMap(\.providerID))
        sharedProviders = currentProviders.intersection(previousProviders)
        excludedProviders = currentProviders.symmetricDifference(previousProviders)
    }

    func includes(_ item: BackupInventoryItem) -> Bool {
        guard let provider = item.providerID else { return false }
        return sharedProviders.contains(provider)
    }
}
