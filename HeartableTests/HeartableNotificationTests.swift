import XCTest
@testable import Heartable

@MainActor
final class HeartableNotificationTests: XCTestCase {
    func testNotificationsQueueWithoutReplacingTheVisibleMessage() async {
        let center = BannerCenter()

        center.success("Profile saved")
        center.error("Couldn’t refresh library")

        XCTAssertEqual(center.current?.message, "Profile saved")
        XCTAssertEqual(center.current?.style, .success)

        center.dismiss()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(center.current?.message, "Couldn’t refresh library")
        XCTAssertEqual(center.current?.style, .error)
        center.dismiss()
    }

    func testDuplicateVisibleNotificationIsNotQueued() async {
        let center = BannerCenter()

        center.info("Already connected")
        center.info("Already connected")
        center.dismiss()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertNil(center.current)
    }
}
