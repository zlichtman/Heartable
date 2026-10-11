import Foundation
import Observation

/// Injectable backend seam for the activity repository. Production uses
/// `BackendAPI`; tests can supply deterministic closures without Supabase.
struct FriendActivityClient: Sendable {
    var fetch:
        @Sendable (Int, FriendActivityCursor?) async throws
            -> [FriendActivityEntryDTO]
    var setReaction:
        @Sendable (UUID, FriendActivityReaction?) async throws
            -> Void

    static let live = FriendActivityClient(
        fetch: { limit, cursor in
            try await BackendAPI.shared.fetchFriendActivity(
                limit: limit,
                before: cursor
            )
        },
        setReaction: { activityID, reaction in
            try await BackendAPI.shared.setFriendActivityReaction(
                activityID: activityID,
                reaction: reaction
            )
        }
    )
}

/// Account-scoped stale-while-revalidate store for the historical friends feed.
///
/// `load` publishes a disk or memory snapshot before revalidating it. A failed
/// refresh never replaces that last-good snapshot with an empty feed. Reactions
/// update optimistically, with a rollback when the server rejects the mutation.
@MainActor
@Observable
final class FriendActivityRepository {
    private struct DiskSnapshot: Codable, Sendable {
        static let currentVersion = 1

        let version: Int
        let ownerID: UUID
        let entries: [FriendActivityEntryDTO]
        let fetchedAt: Date
    }

    private actor CacheIO {
        func load(from url: URL, ownerID: UUID) -> DiskSnapshot? {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(
                      DiskSnapshot.self,
                      from: data
                  ),
                  snapshot.version == DiskSnapshot.currentVersion,
                  snapshot.ownerID == ownerID else {
                return nil
            }
            return snapshot
        }

        func save(_ snapshot: DiskSnapshot, to url: URL) {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    nonisolated static let freshnessWindow: TimeInterval = 2 * 60

    private let client: FriendActivityClient
    private let cacheIO = CacheIO()
    private var hydratedOwnerID: UUID?
    private var lifecycleID = UUID()

    private(set) var entries: [FriendActivityEntryDTO] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = true
    private(set) var reactingActivityIDs: Set<UUID> = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    init(client: FriendActivityClient = .live) {
        self.client = client
    }

    /// Current memory snapshot. This never initiates network work.
    func cached(limit: Int = 50) -> [FriendActivityEntryDTO] {
        Array(entries.prefix(max(0, limit)))
    }

    /// Serve the account's disk/memory snapshot first, then revalidate only when
    /// stale. Awaiting this method waits for revalidation, but observers receive
    /// hydrated entries as soon as disk decoding completes.
    func load(limit: Int = 50, now: Date = Date()) async {
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            reset()
            return
        }
        await hydrate(ownerID: ownerID)
        guard hydratedOwnerID == ownerID else { return }
        guard Self.shouldRefresh(lastUpdated: lastUpdated, now: now, force: false)
        else { return }
        await refresh(limit: limit)
    }

    /// Force a first-page network refresh while retaining the last-good page on
    /// failure.
    func refresh(limit: Int = 50) async {
        guard !isRefreshing,
              let ownerID = AccountSessionStore.currentOwnerID else {
            return
        }
        if hydratedOwnerID != ownerID {
            await hydrate(ownerID: ownerID)
        }
        guard hydratedOwnerID == ownerID else { return }

        let requestLifecycleID = lifecycleID
        isLoading = entries.isEmpty
        isRefreshing = !entries.isEmpty
        errorMessage = nil
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let requested = max(1, min(limit, 100))
            let fetched = try await client.fetch(requested, nil)
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            entries = Self.unique(fetched)
            canLoadMore = fetched.count == requested
            lastUpdated = Date()
            await persist(ownerID: ownerID)
        } catch {
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch the next keyset page. Existing entries are never discarded if that
    /// request fails, and duplicate ids are removed defensively.
    func loadMore(limit: Int = 50) async {
        guard !isLoadingMore,
              canLoadMore,
              !entries.isEmpty,
              let cursor = entries.last?.cursor,
              let ownerID = AccountSessionStore.currentOwnerID,
              hydratedOwnerID == ownerID else {
            return
        }
        let requestLifecycleID = lifecycleID
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let requested = max(1, min(limit, 100))
            let fetched = try await client.fetch(requested, cursor)
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            entries = Self.unique(entries + fetched)
            canLoadMore = fetched.count == requested
            await persist(ownerID: ownerID)
        } catch {
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Selecting the active reaction removes it; selecting another replaces it.
    /// Counts and viewer state change immediately, then roll back if RLS or the
    /// network rejects the authoritative mutation.
    func toggleReaction(
        activityID: UUID,
        reaction: FriendActivityReaction
    ) async {
        guard !reactingActivityIDs.contains(activityID),
              let index = entries.firstIndex(where: { $0.id == activityID }),
              let ownerID = AccountSessionStore.currentOwnerID,
              hydratedOwnerID == ownerID else {
            return
        }
        let requestLifecycleID = lifecycleID
        let previous = entries[index]
        let nextReaction =
            previous.viewerReaction == reaction ? nil : reaction
        entries[index] = Self.applyingReaction(nextReaction, to: previous)
        reactingActivityIDs.insert(activityID)
        errorMessage = nil

        do {
            try await client.setReaction(activityID, nextReaction)
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            await persist(ownerID: ownerID)
        } catch {
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            if let rollbackIndex = entries.firstIndex(where: {
                $0.id == activityID
            }) {
                entries[rollbackIndex] = previous
            }
            errorMessage = error.localizedDescription
        }
        guard ownsCurrentLifecycle(
            ownerID: ownerID,
            requestLifecycleID: requestLifecycleID
        ) else { return }
        reactingActivityIDs.remove(activityID)
    }

    /// Clears in-memory identity on sign-out/account transition. Account-scoped
    /// disk snapshots cannot be read by another Heartable account.
    func reset() {
        lifecycleID = UUID()
        hydratedOwnerID = nil
        entries = []
        isLoading = false
        isRefreshing = false
        isLoadingMore = false
        canLoadMore = true
        reactingActivityIDs = []
        lastUpdated = nil
        errorMessage = nil
    }

    nonisolated static func shouldRefresh(
        lastUpdated: Date?,
        now: Date = Date(),
        force: Bool
    ) -> Bool {
        if force { return true }
        guard let lastUpdated else { return true }
        let age = now.timeIntervalSince(lastUpdated)
        return age < 0 || age >= freshnessWindow
    }

    nonisolated static func applyingReaction(
        _ reaction: FriendActivityReaction?,
        to entry: FriendActivityEntryDTO
    ) -> FriendActivityEntryDTO {
        var updated = entry
        if let previous = updated.viewerReaction {
            let key = previous.rawValue
            let count = max(0, (updated.reactionCounts[key] ?? 0) - 1)
            if count == 0 {
                updated.reactionCounts.removeValue(forKey: key)
            } else {
                updated.reactionCounts[key] = count
            }
        }
        if let reaction {
            updated.reactionCounts[reaction.rawValue, default: 0] += 1
        }
        updated.viewerReaction = reaction
        return updated
    }

    private func hydrate(ownerID: UUID) async {
        guard hydratedOwnerID != ownerID else { return }
        reset()
        let requestLifecycleID = lifecycleID
        guard let url = Self.cacheURL(ownerID: ownerID) else {
            hydratedOwnerID = ownerID
            return
        }
        let snapshot = await cacheIO.load(from: url, ownerID: ownerID)
        guard AccountSessionStore.currentOwnerID == ownerID,
              lifecycleID == requestLifecycleID else {
            return
        }
        if let snapshot {
            entries = Self.unique(snapshot.entries)
            lastUpdated = snapshot.fetchedAt
        }
        hydratedOwnerID = ownerID
    }

    private func persist(ownerID: UUID) async {
        guard hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID,
              let lastUpdated,
              let url = Self.cacheURL(ownerID: ownerID) else {
            return
        }
        let snapshot = DiskSnapshot(
            version: DiskSnapshot.currentVersion,
            ownerID: ownerID,
            entries: entries,
            fetchedAt: lastUpdated
        )
        await cacheIO.save(snapshot, to: url)
    }

    private func ownsCurrentLifecycle(
        ownerID: UUID,
        requestLifecycleID: UUID
    ) -> Bool {
        lifecycleID == requestLifecycleID
            && hydratedOwnerID == ownerID
            && AccountSessionStore.currentOwnerID == ownerID
    }

    private nonisolated static func unique(
        _ entries: [FriendActivityEntryDTO]
    ) -> [FriendActivityEntryDTO] {
        var seen = Set<UUID>()
        return entries.filter { seen.insert($0.id).inserted }
    }

    private nonisolated static func cacheURL(ownerID: UUID) -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
            .appendingPathComponent(
                AccountSessionStore.scopedFilename(
                    "friend-activity",
                    ext: "json",
                    ownerID: ownerID
                )
            )
    }
}
