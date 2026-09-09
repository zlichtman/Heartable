import XCTest
@testable import Heartable

final class SpotifyAPITests: XCTestCase {
    func testTopTracksLimitMatchesSpotifyContract() {
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(100), 50)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(50), 50)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(25), 25)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(0), 1)
    }
}
