import XCTest
@testable import Heartable

final class SpotifyPlaylistPagingTests: XCTestCase {
    private static func page(_ json: String) throws -> Paged<PlaylistTrackItem> {
        try JSONDecoder().decode(Paged<PlaylistTrackItem>.self, from: Data(json.utf8))
    }

    func testBothRowShapesDecodeAndTheCursorCountsUnavailableRows() async throws {
        let result = try await SpotifyAPI.readPlaylistTrackPages(token: "t", id: "p", transform: { $0.id }, gap: .zero) { _, _, offset in
            switch offset {
            case 0: return try Self.page(#"{"items":[{"item":null},{"item":{"id":"one","uri":"spotify:track:one"}},{"track":{"id":"two","uri":"spotify:track:two"}}],"next":"n"}"#)
            case 3: return try Self.page(#"{"items":[{"item":{"id":"three","uri":"spotify:track:three"}}],"next":null}"#)
            default: throw ProviderError("Repeated or incorrect page offset: \(offset)")
            }
        }
        XCTAssertEqual(result, ["one", "two", "three"])
    }

    func testCancellationStopsBeforeTheNextRequest() async {
        actor Calls { var count = 0; func bump() { count += 1 } }
        let calls = Calls()
        let task = Task {
            try await SpotifyAPI.readPlaylistTrackPages(token: "t", id: "p", transform: { $0.id }, gap: .zero) { _, _, offset in
                await calls.bump()
                if offset == 0 { withUnsafeCurrentTask { $0?.cancel() } }
                return try Self.page(#"{"items":[{"item":{"id":"\#(offset)","uri":"u"}}],"next":"n"}"#)
            }
        }
        let outcome = await task.result
        guard case .failure(let error) = outcome else { return XCTFail("A cancelled read must not claim success") }
        XCTAssertTrue(error is CancellationError)
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testPagingPastSpotifysPlaylistCeilingFails() async {
        do {
            _ = try await SpotifyAPI.readPlaylistTrackPages(token: "t", id: "p", maxItems: 100, transform: { $0.id }, gap: .zero) { _, _, offset in
                try Self.page(#"{"items":[\#((0..<50).map { _ in #"{"item":{"id":"x","uri":"u"}}"# }.joined(separator: ","))],"next":"n"}"#)
            }
            XCTFail("An endless playlist must fail instead of accumulating forever")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }
}
