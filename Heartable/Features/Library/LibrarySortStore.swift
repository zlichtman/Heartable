import Foundation
import Observation

/// Drives the Library playlists toolbar: grid/list layout and the sort mode, plus
/// the two user-customizable orderings (a manual playlist order and the per-provider
/// priority used by Creator sort) and the per-playlist "last played from" stamps
/// that power Recent. Layout and sort modes are device appearance preferences;
/// the custom order, provider priority and last-played stamps describe one
/// account's playlists, so they persist under account-scoped keys and are
/// reloaded on every account transition.
@MainActor
@Observable
final class LibrarySortStore {
    enum Layout: String, Codable { case grid, list }

    enum ArtistSortMode: String, Codable, CaseIterable, Identifiable {
        case alphabetical
        case songCount

        var id: String { rawValue }

        var label: String {
            switch self {
            case .alphabetical: "A–Z"
            case .songCount: "Song Count"
            }
        }

        var icon: String {
            switch self {
            case .alphabetical: "textformat"
            case .songCount: "number"
            }
        }
    }

    enum SortMode: String, Codable, CaseIterable {
        // Declaration order = tap-cycle order: A–Z, Recent, Creator, Custom.
        case alphabetical, recent, creator, custom

        var label: String {
            switch self {
            case .recent: "Recent"
            case .custom: "Custom"
            case .alphabetical: "A–Z"
            case .creator: "Creator"
            }
        }

        var icon: String {
            switch self {
            case .recent: "clock"
            case .custom: "hand.draw"
            case .alphabetical: "textformat"
            case .creator: "person.2"
            }
        }

        /// Long-pressing the sort button only customizes these two modes.
        var isReorderable: Bool { self == .custom || self == .creator }
    }

    private enum Keys {
        static let layout = "lib_layout"
        static let sort = "lib_sort"
        static let artistSort = "lib_artist_sort"
        static let custom = "lib_custom_order"
        static let providers = "lib_provider_order"
        static let lastPlayed = "lib_last_played"
    }

    var layout: Layout { didSet { persist(layout.rawValue, Keys.layout) } }
    var sortMode: SortMode { didSet { persist(sortMode.rawValue, Keys.sort) } }
    var artistSortMode: ArtistSortMode {
        didSet { persist(artistSortMode.rawValue, Keys.artistSort) }
    }

    /// Manual order of playlist keys (Custom sort). New keys land at the top.
    private(set) var customOrder: [String]
    /// Provider priority for Creator sort (mixtapes are always pinned first).
    private(set) var providerOrder: [ProviderID]
    /// playlist key -> epoch seconds of the last time playback started from it.
    private var lastPlayed: [String: TimeInterval]

    private let defaults = UserDefaults.standard
    private var ownerID: UUID?

    init() {
        let d = UserDefaults.standard
        layout = Layout(rawValue: d.string(forKey: Keys.layout) ?? "") ?? .grid
        sortMode = SortMode(rawValue: d.string(forKey: Keys.sort) ?? "") ?? .alphabetical
        artistSortMode = ArtistSortMode(
            rawValue: d.string(forKey: Keys.artistSort) ?? ""
        ) ?? .alphabetical
        customOrder = []
        lastPlayed = [:]
        providerOrder = Self.seededProviderOrder(restored: [])
    }

    /// Loads the orderings owned by `ownerID`, or clears them when nil.
    func activate(ownerID: UUID?) {
        self.ownerID = ownerID
        customOrder = (AccountSessionStore.defaultObject(forKey: Keys.custom, ownerID: ownerID) as? [String]) ?? []
        lastPlayed = (AccountSessionStore.defaultObject(forKey: Keys.lastPlayed, ownerID: ownerID)
            as? [String: TimeInterval]) ?? [:]
        let saved = (AccountSessionStore.defaultObject(forKey: Keys.providers, ownerID: ownerID) as? [String]) ?? []
        providerOrder = Self.seededProviderOrder(restored: saved.compactMap(ProviderID.init(rawValue:)))
    }

    /// Account shell reset: forget the previous account's orderings in memory.
    func reset() { activate(ownerID: nil) }

    /// Seed/repair so new sources still appear. Heartable Mixtapes (`.heartable`)
    /// is a normal, reorderable entry — defaults first but isn't pinned there.
    private static func seededProviderOrder(restored: [ProviderID]) -> [ProviderID] {
        let seed = [.heartable] + ProviderCatalog.all.map(\.id)
        return restored + seed.filter { !restored.contains($0) }
    }

    // MARK: - Mutations

    func cycleSort() {
        let all = SortMode.allCases
        let i = all.firstIndex(of: sortMode) ?? 0
        sortMode = all[(i + 1) % all.count]
    }

    func cycleArtistSort() {
        artistSortMode = artistSortMode == .alphabetical ? .songCount : .alphabetical
    }

    func recordPlayed(_ key: String) {
        lastPlayed[key] = Date().timeIntervalSince1970
        AccountSessionStore.setDefault(lastPlayed, forKey: Keys.lastPlayed, ownerID: ownerID)
    }

    func setCustomOrder(_ keys: [String]) {
        customOrder = keys
        AccountSessionStore.setDefault(keys, forKey: Keys.custom, ownerID: ownerID)
    }

    func setProviderOrder(_ order: [ProviderID]) {
        providerOrder = order
        AccountSessionStore.setDefault(order.map(\.rawValue), forKey: Keys.providers, ownerID: ownerID)
    }

    // MARK: - Sorting

    /// Returns `playlists` in the active sort order. For Custom, also folds any
    /// keys not yet in `customOrder` in at the top (newest-first) and persists.
    func sorted(_ playlists: [UnifiedPlaylist]) -> [UnifiedPlaylist] {
        switch sortMode {
        case .alphabetical:
            return playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        case .recent:
            return playlists.sorted { a, b in
                let pa = lastPlayed[a.key] ?? -1, pb = lastPlayed[b.key] ?? -1
                if pa != pb { return pa > pb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

        case .custom:
            syncCustomOrder(with: playlists)
            // A repeated key must never trap the Library tab; the first position wins.
            let rank = Dictionary(customOrder.enumerated().map { ($0.element, $0.offset) },
                                  uniquingKeysWith: { first, _ in first })
            return playlists.sorted { (rank[$0.key] ?? .max) < (rank[$1.key] ?? .max) }

        case .creator:
            return playlists.sorted { a, b in
                let ga = creatorGroup(a), gb = creatorGroup(b)
                if ga != gb { return ga < gb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Creator group rank: position of the source (including Heartable Mixtapes)
    /// in the user-defined `providerOrder`. No source is pinned.
    private func creatorGroup(_ pl: UnifiedPlaylist) -> Int {
        providerOrder.firstIndex(of: pl.providerID) ?? providerOrder.count
    }

    /// Drops keys that no longer exist and prepends newly seen keys (newest-first),
    /// preserving the user's manual ordering for everything already known.
    private func syncCustomOrder(with playlists: [UnifiedPlaylist]) {
        let live = Set(playlists.map(\.key))
        let known = Set(customOrder)
        // New keys: newest createdAt first, then by name, so fresh items land on top.
        let newOnes = playlists.filter { !known.contains($0.key) }.sorted { a, b in
            switch (a.createdAt, b.createdAt) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }.map(\.key)
        let pruned = customOrder.filter { live.contains($0) }
        var seen = Set<String>()
        let merged = (newOnes + pruned).filter { seen.insert($0).inserted }
        if merged != customOrder { setCustomOrder(merged) }
    }

    // MARK: - Helpers

    private func persist(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
}
