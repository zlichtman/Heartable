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

    private(set) var cachedDataReady = false
    private(set) var synchronizing = false

    private var lifecycleID = UUID()
    private var preparationTask: Task<Void, Never>?
    private var synchronizationTask: Task<Void, Never>?
    private var synchronizationID: UUID?

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
    func prepareCachedData(using playlistTracks: PlaylistTracksRepository) async {
        if cachedDataReady { return }
        if let preparationTask {
            await preparationTask.value
            return
        }

        let requestID = lifecycleID
        let library = library
        let master = master
        let task = Task {
            async let libraryHydration: Void = library.hydrate()
            async let playlistHydration: Void = playlistTracks.hydrate()
            async let masterHydration: Void = master.hydrate()

            await libraryHydration
            await playlistHydration
            guard !Task.isCancelled else { return }
            await library.restoreArtistIndex(from: playlistTracks)
            await masterHydration
        }
        preparationTask = task
        await task.value

        guard lifecycleID == requestID, !task.isCancelled else { return }
        cachedDataReady = true
        preparationTask = nil
    }

    /// Refreshes provider metadata first, then reconciles the expensive playlist
    /// and artist index. The task belongs to the account shell rather than the
    /// Library view, so switching tabs cannot cancel or restart it.
    func synchronize(
        providers: [MusicProvider],
        playlistTracks: PlaylistTracksRepository,
        force: Bool = false
    ) async {
        await prepareCachedData(using: playlistTracks)

        if let synchronizationTask {
            let activeID = synchronizationID
            await synchronizationTask.value
            if synchronizationID == activeID {
                self.synchronizationTask = nil
                synchronizationID = nil
                synchronizing = false
            }
            if force {
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
        synchronizing = false
    }

    /// Cancels old-account work and clears every account-owned projection while
    /// retaining the store identities injected into SwiftUI.
    func reset() {
        lifecycleID = UUID()
        preparationTask?.cancel()
        synchronizationTask?.cancel()
        preparationTask = nil
        synchronizationTask = nil
        synchronizationID = nil
        cachedDataReady = false
        synchronizing = false
        library.reset()
        master.reset()
    }
}
