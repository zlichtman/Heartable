import Foundation

/// Routes by ProviderID. Live adapters override the stub. Catalog order keeps
/// the picker consistent.
enum ProviderRegistry {
    /// One long-lived adapter per catalog entry. The catalog is the single place
    /// where a new provider declares its adapter, presentation, capabilities,
    /// playback quality, and transport route.
    private static let adapters: [ProviderID: any MusicProvider] = Dictionary(
        uniqueKeysWithValues: ProviderCatalog.all.map { ($0.id, $0.makeProvider()) }
    )

    static func provider(for id: ProviderID) -> MusicProvider {
        adapters[id] ?? StubProvider(id: id)
    }

    /// One provider per catalog entry, in catalog order.
    static var all: [MusicProvider] { ProviderCatalog.all.map { provider(for: $0.id) } }

    static func providerForTrack(_ track: UnifiedTrack) -> MusicProvider {
        provider(for: track.providerID)
    }

    static func playUnified(_ track: UnifiedTrack) async throws {
        try await providerForTrack(track).play(track)
    }

    static func connected() async -> [MusicProvider] {
        // Public catalogs are search sources, never personal libraries or stats.
        let live = all.filter { ProviderCatalog.entry($0.id)?.requiresAccountConnection == true }
        // Probe concurrently, gather the connected ids, then rebuild in catalog order.
        let connectedIDs = await withTaskGroup(of: ProviderID?.self) { group -> Set<ProviderID> in
            for p in live {
                group.addTask { await p.isConnected() ? p.id : nil }
            }
            var ids: Set<ProviderID> = []
            for await id in group {
                if let id { ids.insert(id) }
            }
            return ids
        }
        return live.filter { connectedIDs.contains($0.id) }
    }

    static func searchable() async -> [MusicProvider] {
        let connectedIDs = Set(await connected().map(\.id))
        return all.filter {
            guard let entry = ProviderCatalog.entry($0.id),
                  entry.status == .live, entry.capabilities.contains(.search) else { return false }
            return entry.isPublicSearch || connectedIDs.contains($0.id)
        }
    }
}
