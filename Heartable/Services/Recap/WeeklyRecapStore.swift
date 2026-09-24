import Foundation
import Observation

struct WeeklyRecapClient: Sendable {
    var fetchAllHistory: @Sendable () async -> [PlayEntryDTO]?

    static let live = WeeklyRecapClient(
        fetchAllHistory: {
            await BackendAPI.shared.fetchAllPlayHistory()
        }
    )
}

/// Cache-first state for the recap screen. It publishes the durable local
/// snapshot immediately, then re-derives every week from the complete real
/// `play_log` ledger. Failed refreshes never erase a last-good recap.
@MainActor
@Observable
final class WeeklyRecapStore {
    private let client: WeeklyRecapClient
    private let archive: WeeklyRecapArchiveStore
    private var lifecycleID = UUID()
    private var loadedOwnerID: UUID?

    private(set) var current: WeeklyRecap?
    private(set) var archived: [WeeklyRecap] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    init(
        client: WeeklyRecapClient = .live,
        archive: WeeklyRecapArchiveStore = WeeklyRecapArchiveStore()
    ) {
        self.client = client
        self.archive = archive
    }

    func load(now: Date = Date(), force: Bool = false) async {
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            reset()
            return
        }

        if loadedOwnerID != ownerID {
            reset()
            loadedOwnerID = ownerID
            isLoading = true
            let hydrationID = lifecycleID
            if let snapshot = await archive.load(ownerID: ownerID),
               lifecycleID == hydrationID,
               loadedOwnerID == ownerID {
                current = snapshot.current
                archived = snapshot.completed
                lastUpdated = snapshot.savedAt
            }
            isLoading = current == nil && archived.isEmpty
        }
        let requestID = lifecycleID

        if !force,
           let lastUpdated,
           now.timeIntervalSince(lastUpdated) < 5 * 60 {
            isLoading = false
            return
        }

        if current == nil && archived.isEmpty {
            isLoading = true
        } else {
            isRefreshing = true
        }
        errorMessage = nil

        guard let entries = await client.fetchAllHistory() else {
            guard loadedOwnerID == ownerID, lifecycleID == requestID else { return }
            isLoading = false
            isRefreshing = false
            errorMessage = "Couldn’t refresh your recap. Showing the last saved week."
            return
        }
        guard loadedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID,
              lifecycleID == requestID else {
            return
        }

        let collection = await Task.detached(priority: .userInitiated) {
            WeeklyRecapBuilder.makeCollection(entries: entries, now: now)
        }.value
        guard loadedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID,
              lifecycleID == requestID else {
            return
        }

        current = collection.current
        archived = collection.completed
        lastUpdated = now
        isLoading = false
        isRefreshing = false
        await archive.replace(
            ownerID: ownerID,
            current: collection.current,
            completed: collection.completed,
            savedAt: now
        )
        WidgetSnapshotStore.update(
            weeklyRecap: collection.current.isEmpty ? nil : collection.current
        )
    }

    func refresh(now: Date = Date()) async {
        await load(now: now, force: true)
    }

    func reset() {
        lifecycleID = UUID()
        loadedOwnerID = nil
        current = nil
        archived = []
        isLoading = false
        isRefreshing = false
        lastUpdated = nil
        errorMessage = nil
    }

    func clear(ownerID: UUID) async {
        await archive.clear(ownerID: ownerID)
        if loadedOwnerID == ownerID { reset() }
        WidgetSnapshotStore.update(weeklyRecap: Optional<WeeklyRecap>.none)
    }
}
