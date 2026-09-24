import XCTest
@testable import Heartable

final class Build94RegressionTests: XCTestCase {
    func testSpotifyIdentityIncludesPhotoAndToleratesNoPhoto() throws {
        let decoder = JSONDecoder()
        let full = try decoder.decode(SpotifyUser.self, from: Data(#"{"id":"aaron","display_name":"Aaron Lichtman","images":[{"url":"https://example.com/a.jpg"}]}"#.utf8))
        XCTAssertEqual(full.displayName, "Aaron Lichtman")
        XCTAssertEqual(full.images?.first?.url, "https://example.com/a.jpg")
        let empty = try decoder.decode(SpotifyUser.self, from: Data(#"{"id":"aaron"}"#.utf8))
        XCTAssertNil(empty.images)
    }

    @MainActor func testInitialsHandleWhitespaceAndMultipleWords() {
        XCTAssertEqual(AvatarCircle.initials(for: " Aaron Lichtman "), "AL")
        XCTAssertEqual(AvatarCircle.initials(for: "Prince"), "P")
        XCTAssertEqual(AvatarCircle.initials(for: "  \n"), "?")
    }

    func testPlaylistErrorsDistinguishAccessRateLimitAndNetwork() {
        XCTAssertTrue(SpotifyPlaylistFailure.message(for: SpotifyPlaylistHTTPError(status: 403)).contains("403"))
        XCTAssertTrue(SpotifyPlaylistFailure.message(for: SpotifyPlaylistHTTPError(status: 403)).contains("owns"))
        XCTAssertTrue(SpotifyPlaylistFailure.message(for: SpotifyPlaylistHTTPError(status: 404)).contains("404"))
        XCTAssertTrue(SpotifyPlaylistFailure.message(for: SpotifyReadBackoff.Limited(retryAfter: 125)).contains("3 minutes"))
        XCTAssertTrue(SpotifyPlaylistFailure.message(for: URLError(.notConnectedToInternet)).contains("offline"))
    }

    func testProviderDiagnosticsDeduplicateWithoutPrivateData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticsStore(directory: directory)
        await store.record(kind: "crash", build: "91", summary: "watchdog", payloadJSON: "{}")
        for _ in 0..<40 { await store.recordProviderFailure(code: "http_403", summary: "Spotify access denied") }
        let entries = await store.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last?.kind, "crash")
        XCTAssertEqual(entries.first?.payloadJSON, #"{"provider":"spotify","operation":"playlist_items","code":"http_403"}"#)
    }
}
