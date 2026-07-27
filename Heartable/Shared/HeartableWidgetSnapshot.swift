import Foundation

/// Secret-free, Codable handoff shared by the app and WidgetKit extension.
/// Widgets never open Supabase or provider credentials; the signed-in app writes
/// this small snapshot after successful recap/activity refreshes.
struct HeartableWidgetSnapshot: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    let generatedAt: Date
    var weeklyRecap: WidgetWeeklyRecapSnapshot?
    var friendActivity: [WidgetFriendActivitySnapshot]

    static func empty(at date: Date = Date()) -> HeartableWidgetSnapshot {
        HeartableWidgetSnapshot(
            version: currentVersion,
            generatedAt: date,
            weeklyRecap: nil,
            friendActivity: []
        )
    }
}

struct WidgetWeeklyRecapSnapshot: Codable, Sendable, Equatable {
    let weekStart: Date
    let weekEnd: Date
    let playCount: Int
    let estimatedListeningMilliseconds: Int64
    let topTrackTitle: String?
    let topTrackArtist: String?
    let topArtistName: String?
}

struct WidgetFriendActivitySnapshot: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let friendName: String
    let trackTitle: String
    let artist: String?
    let playedAt: Date
}

/// Atomic read-modify-write wrapper around the app-group defaults. Separate
/// update methods preserve the other widget's payload when recap and friend
/// activity refresh at different times.
enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.zlichtman.heartable"
    static let recapWidgetKind = "HeartableWeeklyRecapWidget"
    static let friendActivityWidgetKind = "HeartableFriendActivityWidget"

    private static let storageKey = "heartable.widget.snapshot.v1"

    static func load(defaults: UserDefaults? = nil) -> HeartableWidgetSnapshot? {
        guard let defaults = defaults ?? UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(
                HeartableWidgetSnapshot.self,
                from: data
              ),
              snapshot.version == HeartableWidgetSnapshot.currentVersion else {
            return nil
        }
        return snapshot
    }

    static func update(
        weeklyRecap: WidgetWeeklyRecapSnapshot?,
        defaults: UserDefaults? = nil,
        generatedAt: Date = Date()
    ) {
        var snapshot = load(defaults: defaults) ?? .empty(at: generatedAt)
        snapshot = HeartableWidgetSnapshot(
            version: HeartableWidgetSnapshot.currentVersion,
            generatedAt: generatedAt,
            weeklyRecap: weeklyRecap,
            friendActivity: snapshot.friendActivity
        )
        save(snapshot, defaults: defaults)
    }

    static func update(
        friendActivity: [WidgetFriendActivitySnapshot],
        defaults: UserDefaults? = nil,
        generatedAt: Date = Date()
    ) {
        let existing = load(defaults: defaults) ?? .empty(at: generatedAt)
        let snapshot = HeartableWidgetSnapshot(
            version: HeartableWidgetSnapshot.currentVersion,
            generatedAt: generatedAt,
            weeklyRecap: existing.weeklyRecap,
            friendActivity: Array(friendActivity.prefix(3))
        )
        save(snapshot, defaults: defaults)
    }

    static func clear(defaults: UserDefaults? = nil) {
        (defaults ?? UserDefaults(suiteName: appGroupIdentifier))?
            .removeObject(forKey: storageKey)
    }

    private static func save(
        _ snapshot: HeartableWidgetSnapshot,
        defaults: UserDefaults?
    ) {
        guard let defaults = defaults ?? UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
