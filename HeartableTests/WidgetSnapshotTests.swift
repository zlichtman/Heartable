import XCTest
@testable import Heartable

final class WidgetSnapshotTests: XCTestCase {
    func testIndependentUpdatesPreserveTheOtherWidgetPayload() {
        let suiteName = "WidgetSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recap = WidgetWeeklyRecapSnapshot(
            weekStart: Date(timeIntervalSince1970: 100),
            weekEnd: Date(timeIntervalSince1970: 200),
            playCount: 7,
            estimatedListeningMilliseconds: 420_000,
            topTrackTitle: "A Song",
            topTrackArtist: "An Artist",
            topArtistName: "An Artist"
        )
        WidgetSnapshotStore.update(
            weeklyRecap: recap,
            defaults: defaults,
            generatedAt: Date(timeIntervalSince1970: 300)
        )

        let activity = (0..<5).map {
            WidgetFriendActivitySnapshot(
                id: UUID(),
                friendName: "Friend \($0)",
                trackTitle: "Track \($0)",
                artist: "Artist",
                playedAt: Date(timeIntervalSince1970: Double(400 + $0))
            )
        }
        WidgetSnapshotStore.update(
            friendActivity: activity,
            defaults: defaults,
            generatedAt: Date(timeIntervalSince1970: 500)
        )

        let loaded = WidgetSnapshotStore.load(defaults: defaults)
        XCTAssertEqual(loaded?.weeklyRecap, recap)
        XCTAssertEqual(loaded?.friendActivity, Array(activity.prefix(3)))
        XCTAssertEqual(loaded?.generatedAt, Date(timeIntervalSince1970: 500))
    }

    func testClearRemovesAllAccountContent() {
        let suiteName = "WidgetSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        WidgetSnapshotStore.update(
            friendActivity: [
                WidgetFriendActivitySnapshot(
                    id: UUID(),
                    friendName: "Friend",
                    trackTitle: "Track",
                    artist: nil,
                    playedAt: Date()
                ),
            ],
            defaults: defaults
        )
        XCTAssertNotNil(WidgetSnapshotStore.load(defaults: defaults))

        WidgetSnapshotStore.clear(defaults: defaults)

        XCTAssertNil(WidgetSnapshotStore.load(defaults: defaults))
    }
}
