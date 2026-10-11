import Foundation

/// Session-local music source choices. Every connected library starts selected.
/// An explicit set, including empty, preserves the user's individual choices.
struct LibrarySearchScope: Equatable, Sendable {
    var selection: Set<ProviderID>?

    static func selectableProviders(connected: [ProviderID]) -> [ProviderID] {
        let supported = Set(ProviderCatalog.searchableLibraryIDs)
        var seen: Set<ProviderID> = []
        return connected.filter { supported.contains($0) && seen.insert($0).inserted }
    }

    func resolved(connected: Set<ProviderID>) -> Set<ProviderID> {
        let available = connected.intersection(ProviderCatalog.searchableLibraryIDs)
        return selection?.intersection(available) ?? available
    }

    mutating func toggle(_ id: ProviderID, connected: Set<ProviderID>) {
        guard Self.selectableProviders(connected: Array(connected)).contains(id) else { return }
        var next = resolved(connected: connected)
        if !next.insert(id).inserted { next.remove(id) }
        selection = next
    }
}
