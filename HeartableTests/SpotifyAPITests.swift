import XCTest
@preconcurrency import SpotifyiOS
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

    func testStaleConnectTransferPreservesNativeWakeSignal() {
        XCTAssertThrowsError(try SpotifyAPI.validateTransferResponse(status: 404, data: Data())) {
            XCTAssertTrue($0 is NoActiveDeviceError)
        }
        XCTAssertThrowsError(try SpotifyAPI.validateTransferResponse(status: 403,
            data: Data(#"{"error":{"message":"Restriction violated"}}"#.utf8))) {
            XCTAssertTrue($0 is SpotifyPlaybackRestrictedError)
        }
        for status in [401, 429, 500] {
            XCTAssertThrowsError(try SpotifyAPI.validateTransferResponse(status: status, data: Data())) {
                XCTAssertFalse($0 is NoActiveDeviceError)
                XCTAssertFalse($0 is SpotifyPlaybackRestrictedError)
            }
        }
        XCTAssertNoThrow(try SpotifyAPI.validateTransferResponse(status: 204, data: Data()))
    }

    @MainActor
    func testNativeSignInRequiresRefreshableCredentials() {
        XCTAssertNil(SpotifyNativeSignIn.Credentials(accessToken: "sdk", refreshToken: "", expiresIn: 3600))
        XCTAssertNil(SpotifyNativeSignIn.Credentials(accessToken: "", refreshToken: "refresh", expiresIn: 3600))
        XCTAssertNil(SpotifyNativeSignIn.Credentials(accessToken: "sdk", refreshToken: "refresh", expiresIn: -.infinity))
        XCTAssertNil(SpotifyNativeSignIn.Credentials(accessToken: "sdk", refreshToken: "refresh", expiresIn: 0))
        let credentials = SpotifyNativeSignIn.Credentials(accessToken: "web", refreshToken: "refresh", expiresIn: 3599.5)
        XCTAssertEqual(credentials?.expiresIn, 3599)
        XCTAssertEqual(credentials?.refreshToken, "refresh")
    }

    @MainActor
    func testReturningWithoutNativeCallbackReleasesSignInForRetry() async {
        var launches = 0
        let coordinator = SpotifyNativeSignIn(canOpenSpotify: { true }, returnGrace: .zero) { _, _ in
            launches += 1
        }
        for expected in 1...2 {
            let task = Task {
                try await coordinator.signIn(clientID: "fixture", scopes: "user-read-private", ownerID: UUID())
            }
            while launches < expected { await Task.yield() }
            coordinator.applicationDidEnterBackground()
            coordinator.applicationDidBecomeActive()
            do { _ = try await task.value; XCTFail("Abandoned sign-in must cancel") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        XCTAssertEqual(launches, 2)
    }

    @MainActor
    func testNewConnectSupersedesAbandonedRequestAndOldCancellationIsHarmless() async {
        var launches = 0
        let coordinator = SpotifyNativeSignIn(canOpenSpotify: { true }) { _, _ in launches += 1 }
        let first = Task {
            try await coordinator.signIn(clientID: "fixture", scopes: "", ownerID: UUID())
        }
        while launches < 1 { await Task.yield() }
        let second = Task {
            try await coordinator.signIn(clientID: "fixture", scopes: "", ownerID: UUID())
        }
        while launches < 2 { await Task.yield() }
        first.cancel()
        do { _ = try await first.value; XCTFail("Superseded request must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        second.cancel()
        do { _ = try await second.value; XCTFail("Expected explicit cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(launches, 2)
    }

    @MainActor
    func testNativeDelegateFailureFromBackgroundQueueAllowsAnotherAttempt() async {
        var launches = 0
        let coordinator = SpotifyNativeSignIn(canOpenSpotify: { true }) { manager, _ in
            launches += 1
            DispatchQueue.global().async {
                manager.delegate?.sessionManager(manager: manager,
                    didFailWith: NSError(domain: "fixture", code: 1))
            }
        }
        for _ in 0..<2 {
            do {
                _ = try await coordinator.signIn(clientID: "fixture", scopes: "", ownerID: UUID())
                XCTFail("Expected the SDK refusal")
            } catch { XCTAssertTrue(error.localizedDescription.contains("could not finish")) }
        }
        XCTAssertEqual(launches, 2)
    }

    func testTopTracksLimitMatchesSpotifyContract() {
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(100), 50)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(50), 50)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(25), 25)
        XCTAssertEqual(SpotifyAPI.normalizedTopTracksLimit(0), 1)
    }
}
