import XCTest
@testable import Heartable

final class ShuffleTests: XCTestCase {
    func testOrderModePreservesInput() {
        let input = ["one", "two", "three"]
        XCTAssertEqual(orderForPlayback(input, mode: .order, weights: [:]), input)
    }

    func testShuffleModesReturnEveryTrackExactlyOnce() {
        let input = Array(0..<100).map(String.init)

        for mode in [ShuffleMode.shuffle, .weighted] {
            let result = orderForPlayback(
                input,
                mode: mode,
                weights: ["1": 100, "2": -100]
            )
            XCTAssertEqual(result.count, input.count)
            XCTAssertEqual(Set(result), Set(input))
        }
    }
}

@MainActor
final class GhostModeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFixedDurationsProduceExpectedExpiry() {
        XCTAssertEqual(
            GhostModeDuration.oneHour.expiration(startingAt: now),
            now.addingTimeInterval(60 * 60)
        )
        XCTAssertEqual(
            GhostModeDuration.eightHours.expiration(startingAt: now),
            now.addingTimeInterval(8 * 60 * 60)
        )
        XCTAssertNil(GhostModeDuration.indefinite.expiration(startingAt: now))
    }

    func testUntilTomorrowUsesNextLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 26,
                hour: 15,
                minute: 30
            )
        )!
        let expected = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 27
            )
        )

        XCTAssertEqual(
            GhostModeDuration.untilTomorrow.expiration(
                startingAt: start,
                calendar: calendar
            ),
            expected
        )
    }

    func testLegacyBooleanRestoresAsIndefinite() {
        let suite = "GhostModeTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "heartable_ghost_mode")

        let store = PlaybackPrefsStore(defaults: defaults, now: now)
        XCTAssertTrue(store.ghostMode)
        XCTAssertTrue(store.ghostModeIndefinite)
        XCTAssertNil(store.ghostModeUntil)
        XCTAssertEqual(
            store.ghostModeStatus(now: now),
            "On until you turn it off"
        )
    }

    func testTimedModePersistsAndExpiresOnReconciliation() {
        let suite = "GhostModeTests.timed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = PlaybackPrefsStore(defaults: defaults, now: now)
        first.enableGhostMode(for: .oneHour, now: now)
        XCTAssertTrue(first.isGhostModeEnabled(at: now))
        XCTAssertEqual(
            first.ghostModeUntil,
            now.addingTimeInterval(60 * 60)
        )

        let restored = PlaybackPrefsStore(
            defaults: defaults,
            now: now.addingTimeInterval(30 * 60)
        )
        XCTAssertTrue(
            restored.isGhostModeEnabled(
                at: now.addingTimeInterval(30 * 60)
            )
        )

        restored.refreshGhostMode(
            now: now.addingTimeInterval(60 * 60)
        )
        XCTAssertFalse(
            restored.isGhostModeEnabled(
                at: now.addingTimeInterval(60 * 60)
            )
        )
        XCTAssertNil(restored.ghostModeUntil)
        XCTAssertFalse(
            defaults.bool(forKey: "heartable_ghost_mode")
        )
        XCTAssertNil(
            defaults.object(forKey: "heartable_ghost_mode_until")
        )
    }

    func testDisabledBooleanDoesNotReviveOrphanedExpiry() {
        let suite = "GhostModeTests.orphan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "heartable_ghost_mode")
        defaults.set(
            now.addingTimeInterval(60 * 60),
            forKey: "heartable_ghost_mode_until"
        )

        let store = PlaybackPrefsStore(defaults: defaults, now: now)
        XCTAssertFalse(store.isGhostModeEnabled(at: now))
        XCTAssertNil(store.ghostModeUntil)
        XCTAssertNil(
            defaults.object(forKey: "heartable_ghost_mode_until")
        )
    }
}
