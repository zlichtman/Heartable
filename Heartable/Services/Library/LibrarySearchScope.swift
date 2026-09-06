import Foundation

/// Session-local search choices. Nil follows connected libraries; an explicit
/// set (including an empty set) is a deliberate multi-selection, not "all".
struct LibrarySearchScope: Equatable, Sendable {
    var selection: Set<ProviderID>?

    func resolved(connected: Set<ProviderID>) -> Set<ProviderID> {
        let available = connected.union(ProviderCatalog.publicSearchIDs).union([.heartable])
        if let selection { return selection.intersection(available) }
        return Set(connected.filter { ProviderCatalog.entry($0)?.section == .library })
            .union([.heartable])
    }

    mutating func toggle(_ id: ProviderID, connected: Set<ProviderID>) {
        var next = resolved(connected: connected)
        if !next.insert(id).inserted { next.remove(id) }
        selection = next
    }
}
