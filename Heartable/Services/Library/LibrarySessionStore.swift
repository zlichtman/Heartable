import Foundation
import Observation

/// Account-scoped owner for the Library/Home browse and search projections.
///
/// The tab view is presentation, so it must not own expensive library state.
/// Keeping these stores above the tab hierarchy means a tab re-selection or
/// navigation-stack rebuild can never restart cache decoding, playlist traversal,
/// or artist aggregation. Cached browse data is published first; provider and
/// artist reconciliation follows as background work owned by the authenticated
/// app shell.
@MainActor
@Observable
final class LibrarySessionStore {
    let library: LibraryStore
    let master: MasterLibraryStore
    let savedRadio = SavedRadioStations()

    private(set) var cachedDataReady = false
    private(set) var synchronizing = false

    private var lifecycleID = UUID()
    private var preparationTask: Task<Void, Never>?
    private var preparationID: UUID?
    private var synchronizationTask: Task<Void, Never>?
    private var synchronizationID: UUID?
    private var synchronizationProviderIDs: Set<ProviderID> = []

    init(
        library: LibraryStore = LibraryStore(),
        master: MasterLibraryStore = MasterLibraryStore()
    ) {
        self.library = library
        self.master = master
    }

    /// Restores every local snapshot once per account. LibraryStore publishes its
    /// playlist/liked-song core as soon as the cache is decoded, before its artist
    /// projection is calculated, so Home becomes useful as early as possible.
    /// `onDecoded` fires once the cached snapshots have been decoded and
    /// published, before the artist projection is restored: that is the whole
    /// window in which a stale cache could crash the app, so callers lower the
    /// launch guard's marker there and nowhere later.
    func prepareCachedData(
        using playlistTracks: PlaylistTracksRepository,
        onDecoded: (@MainActor () -> Void)? = nil
    ) async {
        savedRadio.activate(ownerID: AccountSessionStore.currentOwnerID)
        if cachedDataReady { onDecoded?(); return }
        if let preparationTask {
            await preparationTask.value
            // The runner publishes and clears its own task; a reset or a cleared
            // data set mid-flight leaves nothing published, so hydrate again.
            if cachedDataReady || self.preparationTask != nil { onDecoded?(); return }
        }

        let requestID = lifecycleID
        let runID = UUID()
        let library = library
        let master = master
        let task = Task {
            async let libraryHydration: Void = library.hydrate()
            async let playlistHydration: Void = playlistTracks.hydrate()
            async let masterHydration: Void = master.hydrate()

            await libraryHydration
            await playlistHydration
            onDecoded?()
            guard !Task.isCancelled else { return }
            await library.restoreArtistIndex(from: playlistTracks)
            await masterHydration
        }
        preparationTask = task
        preparationID = runID
        await task.value

        // Whatever happened, this run no longer owns the slot; a later call may
        // hydrate again. Only an uncancelled run for the live account publishes.
        if preparationID == runID {
            preparationTask = nil
            preparationID = nil
        }
        guard lifecycleID == requestID, !task.isCancelled else { return }
        cachedDataReady = true
    }

    /// Refreshes provider metadata first, then reconciles the expensive playlist
    /// and artist index. The task belongs to the account shell rather than the
    /// Library view, so switching tabs cannot cancel or restart it.
    func synchronize(
        providers: [MusicProvider],
        playlistTracks: PlaylistTracksRepository,
        force: Bool = false
    ) async {
        let requestedLifecycleID = lifecycleID
        let requestedProviderIDs = Set(providers.map(\.id))
        await prepareCachedData(using: playlistTracks)
        guard lifecycleID == requestedLifecycleID else { return }

        if let synchronizationTask {
            let activeID = synchronizationID
            let activeProviderIDs = synchronizationProviderIDs
            await synchronizationTask.value
            guard lifecycleID == requestedLifecycleID else { return }
            if synchronizationID == activeID {
                self.synchronizationTask = nil
                synchronizationID = nil
                synchronizationProviderIDs = []
                synchronizing = false
            }
            if Self.shouldRerunSynchronization(
                activeProviderIDs: activeProviderIDs,
                requestedProviderIDs: requestedProviderIDs,
                force: force
            ) {
                await synchronize(
                    providers: providers,
                    playlistTracks: playlistTracks,
                    force: true
                )
            }
            return
        }

        let requestID = lifecycleID
        let operationID = UUID()
        let library = library
        let master = master
        synchronizing = true
        synchronizationID = operationID
        synchronizationProviderIDs = requestedProviderIDs

        let task = Task {
            await library.loadAll(providers: providers, force: force)
            guard !Task.isCancelled else { return }

            // The full playlist walk is deliberately second. Home already has
            // cached content and refreshed playlist metadata at this point.
            await library.loadArtistIndex(using: playlistTracks, force: force)
            guard !Task.isCancelled else { return }

            await master.adopt(
                library.libraryTracks.map(\.track),
                providerIDs: Set(providers.map(\.id))
            )
        }
        synchronizationTask = task
        await task.value

        guard lifecycleID == requestID,
              synchronizationID == operationID else { return }
        synchronizationTask = nil
        synchronizationID = nil
        synchronizationProviderIDs = []
        synchronizing = false
    }

    nonisolated static func shouldRerunSynchronization(
        activeProviderIDs: Set<ProviderID>,
        requestedProviderIDs: Set<ProviderID>,
        force: Bool
    ) -> Bool {
        force || activeProviderIDs != requestedProviderIDs
    }

    /// Cancels old-account work and clears every account-owned projection while
    /// retaining the store identities injected into SwiftUI.
    func reset() {
        lifecycleID = UUID()
        preparationTask?.cancel()
        synchronizationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        synchronizationTask = nil
        synchronizationID = nil
        synchronizationProviderIDs = []
        cachedDataReady = false
        synchronizing = false
        library.reset()
        master.reset()
        savedRadio.activate(ownerID: nil)
    }

    func removeClearedMusicData(ownerID: UUID, playlistTracks: PlaylistTracksRepository) async {
        guard AccountSessionStore.currentOwnerID == ownerID else { return }
        savedRadio.clear(ownerID: ownerID)
        lifecycleID = UUID()
        let requestID = lifecycleID
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        cachedDataReady = false
        synchronizationTask?.cancel()
        await synchronizationTask?.value
        guard lifecycleID == requestID, AccountSessionStore.currentOwnerID == ownerID else { return }
        synchronizationTask = nil
        synchronizationID = nil
        synchronizing = false
        await prepareCachedData(using: playlistTracks)
        guard lifecycleID == requestID, AccountSessionStore.currentOwnerID == ownerID else { return }
        await library.removeOwnedMixtapes(using: playlistTracks)
        guard lifecycleID == requestID, AccountSessionStore.currentOwnerID == ownerID else { return }
        await master.replaceAfterDataClear(library.libraryTracks.map(\.track))
        guard lifecycleID == requestID else { return }
        synchronizationProviderIDs = []
    }
}
