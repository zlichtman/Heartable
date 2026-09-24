import XCTest
@testable import Heartable

final class MixtapeLinksTests: XCTestCase {
    func testOnlyExactBearerLinksAreAccepted() {
        let token = String(repeating: "a1", count: 32)
        XCTAssertEqual(SharedMixtapeRoute.parse(URL(string: "heartable://mixtape?token=\(token)")!)?.token, token)
        XCTAssertNil(SharedMixtapeRoute.parse(URL(string: "https://mixtape?token=\(token)")!))
        XCTAssertFalse(SharedMixtapeRoute.valid(String(repeating: "A", count: 64)))
        XCTAssertFalse(SharedMixtapeRoute.valid(String(repeating: "a", count: 63)))
        XCTAssertFalse(SharedMixtapeRoute.valid(String(repeating: "é", count: 32)))
        XCTAssertEqual(SharedMixtapeRoute.webURL(token: token)?.fragment, token)
        XCTAssertNil(SharedMixtapeRoute.webURL(token: "bad"))
    }
}
