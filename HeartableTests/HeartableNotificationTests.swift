import XCTest
@testable import Heartable

@MainActor
final class HeartableNotificationTests: XCTestCase {
    func testFeedbackRoutesToAppleNotificationDelivery() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter { delivered.append($0) }

        center.success("Profile saved")
        center.error("Couldn’t refresh library")

        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered[0].title, "Heartable")
        XCTAssertEqual(delivered[0].body, "Profile saved")
        XCTAssertEqual(delivered[0].categoryIdentifier, "heartable.feedback.success")
        XCTAssertEqual(delivered[1].categoryIdentifier, "heartable.feedback.error")
    }

    func testDuplicateFeedbackIsCoalesced() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter { delivered.append($0) }

        center.info("Already connected")
        center.info("Already connected")

        XCTAssertEqual(delivered.count, 1)
    }

    func testBlankFeedbackIsNotDelivered() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter { delivered.append($0) }

        center.info("  \n ")

        XCTAssertTrue(delivered.isEmpty)
    }
}
