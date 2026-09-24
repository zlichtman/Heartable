import XCTest
@testable import Heartable

final class SpotifyFailureRetentionWindowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    func testRepeatedFailuresDoNotExtendGraceWindow() {
        var window = SpotifyFailureRetentionWindow()

        XCTAssertTrue(window.shouldRetain(at: start, grace: 30))
        XCTAssertTrue(
            window.shouldRetain(
                at: start.addingTimeInterval(29),
                grace: 30
            )
        )
        XCTAssertFalse(
            window.shouldRetain(
                at: start.addingTimeInterval(30),
                grace: 30
            )
        )
        XCTAssertFalse(
            window.shouldRetain(
                at: start.addingTimeInterval(60),
                grace: 30
            )
        )
    }

    func testSuccessfulPollResetsGraceWindow() {
        var window = SpotifyFailureRetentionWindow()

        XCTAssertTrue(window.shouldRetain(at: start, grace: 30))
        XCTAssertFalse(
            window.shouldRetain(
                at: start.addingTimeInterval(31),
                grace: 30
            )
        )

        window.reset()

        XCTAssertTrue(
            window.shouldRetain(
                at: start.addingTimeInterval(31),
                grace: 30
            )
        )
    }

    func testRateLimitCanExtendGraceThroughNextAllowedPoll() {
        var window = SpotifyFailureRetentionWindow()
        let retryDate = start.addingTimeInterval(120)

        window.extend(through: retryDate)

        XCTAssertTrue(
            window.shouldRetain(
                at: start.addingTimeInterval(119),
                grace: 30
            )
        )
        XCTAssertFalse(
            window.shouldRetain(
                at: retryDate,
                grace: 30
            )
        )
    }

}
