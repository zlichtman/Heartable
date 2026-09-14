import XCTest
@testable import Heartable

final class SpotifyAPITests: XCTestCase {
    func testPlaybackAccountVerificationUsesExactSDKToken() async throws {
        let user = try await SpotifyAPI.playbackUser(token: "sdk-token") { url, headers in
            XCTAssertEqual(url.path, "/v1/me")
            XCTAssertEqual(headers["Authorization"], "Bearer sdk-token")
            return (Data(#"{"id":"sdk-user"}"#.utf8),
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertEqual(user.id, "sdk-user")
    }

    func testRejectedSDKTokenCannotFallBackToWebCredentials() async {
        do {
            _ = try await SpotifyAPI.playbackUser(token: "rejected-sdk-token") { url, _ in
                (Data(), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("Rejected SDK credentials must fail account verification")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
        }
    }

    func testTopTracksLimitMatchesSpotifyContract() {
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(100), 50)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(50), 50)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(25), 25)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(0), 1)
    }
}
