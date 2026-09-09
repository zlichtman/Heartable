import Foundation

/// Session-local search choices. Nil includes every available search source; an explicit
/// set (including an empty set) is a deliberate multi-selection, not "all".
struct LibrarySearchScope: Equatable, Sendable {
    var selection: Set<ProviderID>?

    /// Heartable profiles and radio retain their dedicated result controls;
    /// this menu contains only selectable music services/catalogs.
    static func selectableProviders(connected: [ProviderID]) -> [ProviderID] {
        var seen: Set<ProviderID> = []
        return (connected + ProviderCatalog.publicSearchIDs)
            .filter { $0 != .heartable && $0 != .wsum && seen.insert($0).inserted }
    }

    func resolved(connected: Set<ProviderID>) -> Set<ProviderID> {
        let available = connected.union(ProviderCatalog.publicSearchIDs).union([.heartable])
        if let selection { return selection.intersection(available) }
        return available
    }

    mutating func toggle(_ id: ProviderID, connected: Set<ProviderID>) {
        if selection == nil {
            selection = [id]
            return
        }
        var next = resolved(connected: connected)
        if !next.insert(id).inserted { next.remove(id) }
        selection = next
    }
}
