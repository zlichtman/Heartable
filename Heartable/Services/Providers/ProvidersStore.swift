import Foundation
import Observation

/// Account bootstrap and connection state for every music provider.
///
/// A provider has two distinct truths:
/// - `pairedIDs`: the Heartable account says this service belongs to it.
/// - `connectedIDs`: this installation currently has everything needed to use it.
///
/// Keeping those separate prevents a missing device credential or a transient
/// launch probe from silently turning an account pairing into a disconnect.
@MainActor
@Observable
final class ProvidersStore {
    enum RestorationState: Equatable {
        case inactive
        case restoring
        case ready
    }

    private(set) var connectedIDs: Set<ProviderID> = []
    private(set) var pairedIDs: Set<ProviderID> = []
    private(set) var reconnectRequiredIDs: Set<ProviderID> = []
    private(set) var restorationState: RestorationState = .inactive
    private(set) var hasRefreshed = false
    private(set) var refreshGeneration = 0
    private(set) var isRefreshing = false

    private var ownerID: UUID?
    private var lifecycleID = UUID()
    private var historyImportTask: Task<Void, Never>?

    var isRestoring: Bool { restorationState == .restoring }

    /// Activate one Heartable account. Cached intent is applied immediately, then
    /// reconciled with the RLS-protected server manifest. Provider probes happen
    /// only after the account namespace and restoration metadata are in place.
    func activate(userID: UUID, force: Bool = false) async {
        if ownerID == userID, restorationState == .ready, !force { return }

        if ownerID != userID {
            historyImportTask?.cancel()
            historyImportTask = nil
            lifecycleID = UUID()
            ownerID = userID
            connectedIDs = []
            pairedIDs = []
            reconnectRequiredIDs = []
            hasRefreshed = false
        }
        let requestID = lifecycleID
        restorationState = .restoring

        // Start the authoritative fetch immediately, but don't make the first
        // usable provider state wait on the network. A cached positive pairing
        // can safely restore flags/metadata and probe local Keychain credentials
        // while Supabase is in flight. Cached disconnects are intentionally not
        // applied until they have been timestamp-merged with the server row.
        let remoteTask = Task {
            try? await BackendAPI.shared.providerConnections()
        }
        defer { remoteTask.cancel() }
        let local = Self.accountConnections(Self.cachedManifest(ownerID: userID))
        let cachedConnections = local.filter(\.connected)
        pairedIDs = Set(cachedConnections.compactMap {
            ProviderID(rawValue: $0.providerId)
        })
        await apply(manifest: cachedConnections, requestID: requestID)
        let cachedAvailable = await probeLiveProviders()
        guard lifecycleID == requestID, ownerID == userID else { return }
        connectedIDs = cachedAvailable
        pairedIDs.formUnion(cachedAvailable)
        reconnectRequiredIDs = pairedIDs.subtracting(connectedIDs)

        let remote = await remoteTask.value
        guard lifecycleID == requestID, ownerID == userID else { return }
        var manifest = Self.accountConnections(Self.merge(local: local, remote: remote ?? []))
        await apply(manifest: manifest, requestID: requestID)
        guard lifecycleID == requestID, ownerID == userID else { return }

        let available = await probeLiveProviders()
        guard lifecycleID == requestID, ownerID == userID else { return }

        // Upgrade users who already hold a valid local credential/flag but have no
        // server row yet. An explicit disconnected row always wins.
        let knownIDs = Set(manifest.compactMap { ProviderID(rawValue: $0.providerId) })
        let timestamp = Self.timestamp()
        for id in available where !knownIDs.contains(id) {
            let provider = ProviderRegistry.provider(for: id)
            manifest.append(
                ProviderConnectionDTO(
                    userId: userID,
                    providerId: id.rawValue,
                    connected: true,
                    metadata: await provider.connectionMetadata(),
                    connectedAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }

        let desired = Set(manifest.compactMap { row -> ProviderID? in
            guard row.connected else { return nil }
            return ProviderID(rawValue: row.providerId)
        })
        connectedIDs = available
        pairedIDs = desired.union(available)
        reconnectRequiredIDs = pairedIDs.subtracting(connectedIDs)
        restorationState = .ready
        hasRefreshed = true
        refreshGeneration &+= 1
        Self.cache(manifest, ownerID: userID)
        if connectedIDs.contains(.spotify) { importSpotifyHistory(userID: userID) }

        // Backfill/mend the server manifest after the UI has stable state. This is
        // intentionally best-effort: an offline launch must not disconnect anyone.
        Task { [weak self] in
            guard let self else { return }
            await self.persist(manifest: manifest, requestID: requestID)
        }
    }

    /// Re-probe local availability without changing account-level intent.
    func refresh() async {
        guard ownerID != nil, restorationState == .ready, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let requestID = lifecycleID
        let ids = await probeLiveProviders()
        guard lifecycleID == requestID else { return }
        connectedIDs = ids
        reconnectRequiredIDs = pairedIDs.subtracting(ids)
        hasRefreshed = true
        refreshGeneration &+= 1
    }

    /// Connect locally first, then record the account pairing. A temporary backend
    /// failure is cached and retried on activation; it never undoes a valid token.
    func connect(_ id: ProviderID) async throws {
        guard ProviderCatalog.entry(id)?.requiresAccountConnection == true else { return }
        guard let ownerID else {
            throw ProviderError("Sign in to Heartable before connecting a service.")
        }
        guard restorationState == .ready else {
            throw ProviderError("Heartable is still restoring your services. Try again in a moment.")
        }
        let requestID = lifecycleID
        let provider = ProviderRegistry.provider(for: id)
        try await provider.connect()
        guard lifecycleID == requestID, self.ownerID == ownerID else {
            throw ProviderError("Your Heartable session changed. Connect again.")
        }
        try await recordConnected(provider, ownerID: ownerID, requestID: requestID)
    }

    /// Use after a provider-specific form (currently Jellyfin) has created the
    /// local credential itself.
    func recordConnected(_ id: ProviderID) async throws {
        guard ProviderCatalog.entry(id)?.requiresAccountConnection == true else { return }
        guard let ownerID else {
            throw ProviderError("Sign in to Heartable before connecting a service.")
        }
        let requestID = lifecycleID
        try await recordConnected(
            ProviderRegistry.provider(for: id),
            ownerID: ownerID,
            requestID: requestID
        )
    }

    func disconnect(_ id: ProviderID) async {
        guard ProviderCatalog.entry(id)?.requiresAccountConnection == true else { return }
        if id == .spotify {
            historyImportTask?.cancel()
            historyImportTask = nil
        }
        guard let ownerID else { return }
        let requestID = lifecycleID
        let provider = ProviderRegistry.provider(for: id)
        let metadata = await provider.connectionMetadata()
        await provider.disconnect()
        guard lifecycleID == requestID, self.ownerID == ownerID else { return }

        let row = ProviderConnectionDTO(
            userId: ownerID,
            providerId: id.rawValue,
            connected: false,
            metadata: metadata,
            connectedAt: nil,
            updatedAt: Self.timestamp()
        )
        upsertCached(row, ownerID: ownerID)
        connectedIDs.remove(id)
        pairedIDs.remove(id)
        reconnectRequiredIDs.remove(id)
        hasRefreshed = true
        refreshGeneration &+= 1
        try? await BackendAPI.shared.upsertProviderConnection(
            providerId: id,
            connected: false,
            metadata: metadata,
            userID: ownerID
        )
    }

    func isConnected(_ id: ProviderID) -> Bool { connectedIDs.contains(id) }
    func isPaired(_ id: ProviderID) -> Bool { pairedIDs.contains(id) }
    func requiresReconnect(_ id: ProviderID) -> Bool {
        reconnectRequiredIDs.contains(id)
    }

    /// Forget in-memory state on sign-out/account switch. The account manifest and
    /// scoped Keychain vault deliberately remain intact.
    func reset() {
        historyImportTask?.cancel()
        historyImportTask = nil
        lifecycleID = UUID()
        ownerID = nil
        connectedIDs = []
        pairedIDs = []
        reconnectRequiredIDs = []
        restorationState = .inactive
        hasRefreshed = false
        isRefreshing = false
        refreshGeneration &+= 1
    }

    var connected: [MusicProvider] {
        ProviderRegistry.all.filter { connectedIDs.contains($0.id) }
    }

    // MARK: - Restoration

    private func recordConnected(
        _ provider: MusicProvider,
        ownerID: UUID,
        requestID: UUID
    ) async throws {
        guard await provider.isConnected() else {
            throw ProviderError("The service did not finish connecting. Try again.")
        }
        let metadata = await provider.connectionMetadata()
        guard lifecycleID == requestID, self.ownerID == ownerID else {
            throw ProviderError("Your Heartable session changed. Connect again.")
        }
        let timestamp = Self.timestamp()
        let row = ProviderConnectionDTO(
            userId: ownerID,
            providerId: provider.id.rawValue,
            connected: true,
            metadata: metadata,
            connectedAt: timestamp,
            updatedAt: timestamp
        )
        upsertCached(row, ownerID: ownerID)
        connectedIDs.insert(provider.id)
        pairedIDs.insert(provider.id)
        reconnectRequiredIDs.remove(provider.id)
        hasRefreshed = true
        refreshGeneration &+= 1
        try? await BackendAPI.shared.upsertProviderConnection(
            providerId: provider.id,
            connected: true,
            metadata: metadata,
            userID: ownerID
        )
        if provider.id == .spotify { importSpotifyHistory(userID: ownerID) }
    }

    private func importSpotifyHistory(userID: UUID) {
        historyImportTask?.cancel()
        historyImportTask = Task { await SpotifyHistoryImport.run(ownerID: userID) }
    }

    private func apply(manifest: [ProviderConnectionDTO], requestID: UUID) async {
        for row in manifest {
            guard lifecycleID == requestID,
                  let id = ProviderID(rawValue: row.providerId),
                  ProviderCatalog.entry(id)?.requiresAccountConnection == true else { continue }
            let provider = ProviderRegistry.provider(for: id)
            if row.connected {
                await provider.restoreConnection(metadata: row.metadata)
            } else if await provider.isConnected() {
                await provider.disconnect()
            }
        }
    }

    private func probeLiveProviders() async -> Set<ProviderID> {
        let live = ProviderRegistry.all.filter {
            ProviderCatalog.entry($0.id)?.requiresAccountConnection == true
        }
        return await withTaskGroup(of: ProviderID?.self) { group in
            for provider in live {
                group.addTask {
                    await provider.isConnected() ? provider.id : nil
                }
            }
            var result: Set<ProviderID> = []
            for await id in group {
                if let id { result.insert(id) }
            }
            return result
        }
    }

    private func persist(manifest: [ProviderConnectionDTO], requestID: UUID) async {
        for row in manifest {
            guard lifecycleID == requestID,
                  ownerID == row.userId,
                  AccountSessionStore.currentOwnerID == row.userId,
                  let id = ProviderID(rawValue: row.providerId),
                  ProviderCatalog.entry(id)?.requiresAccountConnection == true else { continue }
            try? await BackendAPI.shared.upsertProviderConnection(
                providerId: id,
                connected: row.connected,
                metadata: row.metadata,
                userID: row.userId
            )
        }
    }

    nonisolated static func accountConnections(_ rows: [ProviderConnectionDTO]) -> [ProviderConnectionDTO] {
        rows.filter {
            guard let id = ProviderID(rawValue: $0.providerId) else { return false }
            return ProviderCatalog.entry(id)?.requiresAccountConnection == true
        }
    }

    // MARK: - Manifest cache

    nonisolated static func merge(
        local: [ProviderConnectionDTO],
        remote: [ProviderConnectionDTO]
    ) -> [ProviderConnectionDTO] {
        var byProvider: [String: ProviderConnectionDTO] = [:]
        for row in remote + local {
            guard let existing = byProvider[row.providerId] else {
                byProvider[row.providerId] = row
                continue
            }
            if Self.isAtLeastAsNew(row.updatedAt, as: existing.updatedAt) {
                byProvider[row.providerId] = row
            }
        }
        return byProvider.values.sorted { $0.providerId < $1.providerId }
    }

    private static func cachedManifest(ownerID: UUID) -> [ProviderConnectionDTO] {
        guard let data = AccountSessionStore.defaultObject(
            forKey: AccountSessionStore.providerManifestCacheKey,
            ownerID: ownerID
        ) as? Data else { return [] }
        return (try? JSONDecoder().decode([ProviderConnectionDTO].self, from: data)) ?? []
    }

    private static func cache(_ rows: [ProviderConnectionDTO], ownerID: UUID) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        AccountSessionStore.setDefault(
            data,
            forKey: AccountSessionStore.providerManifestCacheKey,
            ownerID: ownerID
        )
    }

    private func upsertCached(_ row: ProviderConnectionDTO, ownerID: UUID) {
        let rows = Self.merge(
            local: [row],
            remote: Self.cachedManifest(ownerID: ownerID)
        )
        Self.cache(rows, ownerID: ownerID)
    }

    nonisolated private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    /// PostgREST and Foundation can serialize UTC timestamps with different
    /// fractional-second and timezone spellings. Compare parsed instants rather
    /// than lexicographic strings so a stale row cannot win due to formatting.
    nonisolated private static func isAtLeastAsNew(
        _ candidate: String?,
        as existing: String?
    ) -> Bool {
        guard let existing else { return true }
        guard let candidate else { return false }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ordinary = ISO8601DateFormatter()
        let candidateDate = fractional.date(from: candidate) ?? ordinary.date(from: candidate)
        let existingDate = fractional.date(from: existing) ?? ordinary.date(from: existing)
        if let candidateDate, let existingDate {
            return candidateDate >= existingDate
        }
        return candidate >= existing
    }
}
