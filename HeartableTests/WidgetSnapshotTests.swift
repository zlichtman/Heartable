import XCTest
@testable import Heartable

final class WidgetSnapshotTests: XCTestCase {
    func testExpiredRecapAndFriendActivityAreNotShownAsCurrent() {
        let now = Date(timeIntervalSince1970: 100_000)
        let oldRecap = WidgetWeeklyRecapSnapshot(
            weekStart: now.addingTimeInterval(-604_800), weekEnd: now,
            playCount: 99, estimatedListeningMilliseconds: 1_000,
            topTrackTitle: nil, topTrackArtist: nil, topArtistName: nil
        )
        let recent = WidgetFriendActivitySnapshot(
            id: UUID(), friendName: "Recent", trackTitle: "Song", artist: nil,
            playedAt: now.addingTimeInterval(-60)
        )
        let expired = WidgetFriendActivitySnapshot(
            id: UUID(), friendName: "Old", trackTitle: "Song", artist: nil,
            playedAt: now.addingTimeInterval(-86_400)
        )
        let future = WidgetFriendActivitySnapshot(
            id: UUID(), friendName: "Future", trackTitle: "Song", artist: nil,
            playedAt: now.addingTimeInterval(60)
        )
        let snapshot = HeartableWidgetSnapshot(
            version: HeartableWidgetSnapshot.currentVersion, generatedAt: now,
            weeklyRecap: oldRecap, friendActivity: [recent, expired, future]
        )
        XCTAssertNil(snapshot.displayed(at: now).weeklyRecap)
        XCTAssertEqual(snapshot.displayed(at: now).friendActivity, [recent])
        XCTAssertEqual(snapshot.weeklyRecap, oldRecap)
        XCTAssertEqual(snapshot.displayed(at: now.addingTimeInterval(-1)).weeklyRecap, oldRecap)
    }

    func testWidgetRoutesRoundTripAndRejectUnrelatedURLs() {
        for route in HeartableWidgetRoute.allCases {
            XCTAssertEqual(HeartableWidgetRoute(url: route.url), route)
        }
        for raw in ["https://widget/library", "heartable://add-friend?code=test",
                    "heartable://widget/unknown", "heartable://widget/library/extra",
                    "heartable://widget/library?account=other", "heartable://widget/library#extra",
                    "heartable://user@widget/library"] {
            XCTAssertNil(HeartableWidgetRoute(url: URL(string: raw)!))
        }
    }

    @MainActor
    func testWidgetLinkSurvivesUntilConsumedAndRepeatedTapsWork() {
        let links = WidgetLinks()
        links.handle(HeartableWidgetRoute.recap.url)
        let firstRequest = links.requestID
        XCTAssertEqual(links.pending, .recap)
        XCTAssertEqual(links.take(), .recap)
        XCTAssertNil(links.take())
        links.handle(HeartableWidgetRoute.recap.url)
        XCTAssertNotEqual(firstRequest, links.requestID)
        links.reset()
        XCTAssertNil(links.pending)
        XCTAssertNil(links.requestID)
    }

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
