import Foundation
import Observation

/// Tracks which providers are connected. Injected into the environment; the
/// MusicServices screen + Library read it. Refreshed on launch and after any
/// connect/disconnect.
@MainActor
@Observable
final class ProvidersStore {
    private(set) var connectedIDs: Set<ProviderID> = []
    /// Distinguishes the real "no connected services" result from the empty
    /// placeholder used while the first connection probe is still running.
    private(set) var hasRefreshed = false
    /// Changes after every completed probe, even when the resulting id set is
    /// unchanged. Views can key refresh work to this without starting an
    /// empty-provider request during their first render.
    private(set) var refreshGeneration = 0
    private(set) var isRefreshing = false

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Only catalog-live services are connectable; everything else is greyed and
        // treated as disconnected regardless of any underlying enable flag/token.
        let live = ProviderRegistry.all.filter { ProviderCatalog.entry($0.id)?.status == .live }
        // Probe every live provider concurrently; collect the connected ids off-actor,
        // then hop back to the MainActor to assign the final set.
        let ids = await withTaskGroup(of: ProviderID?.self) { group -> Set<ProviderID> in
            for p in live {
                group.addTask { await p.isConnected() ? p.id : nil }
            }
            var result: Set<ProviderID> = []
            for await id in group {
                if let id { result.insert(id) }
            }
            return result
        }
        connectedIDs = ids
        hasRefreshed = true
        refreshGeneration &+= 1
    }

    func isConnected(_ id: ProviderID) -> Bool { connectedIDs.contains(id) }

    /// Forget connected-provider state (call on sign-out / delete / account switch).
    func reset() {
        connectedIDs = []
        hasRefreshed = false
        refreshGeneration &+= 1
    }

    /// Live, connected providers in catalog order.
    var connected: [MusicProvider] {
        ProviderRegistry.all.filter { connectedIDs.contains($0.id) }
    }
}
