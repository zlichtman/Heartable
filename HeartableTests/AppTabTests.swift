import XCTest
@testable import Heartable

final class AppTabTests: XCTestCase {
    func testRootPageCopyKeepsTheSharedSubtitleStyle() {
        for tab in AppTab.allCases {
            XCTAssertEqual(tab.subtitle, tab.subtitle.lowercased())
            XCTAssertFalse(tab.subtitle.hasSuffix("."))
            XCTAssertTrue(tab.subtitle.contains(", "))
        }
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Heartable", "Chats", "Library", "Backups", "Profile"])
    }
}
