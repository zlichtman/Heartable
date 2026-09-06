import XCTest
@testable import Heartable

final class RadioAndLyricsTests: XCTestCase {
    func testShowFeedRejectsUntrustedLinksAndAutomationAndDeduplicates() throws {
        let rows = [
            event(title: "The Bookshelf", url: "https://spinitron.com/WSUM/show/1/Bookshelf"),
            event(title: "The Bookshelf", url: "https://spinitron.com/WSUM/pl/2/Bookshelf"),
            event(title: "Automated", url: "https://spinitron.com/WSUM/pl/3/A", kind: "automated"),
            event(title: "Unsafe", url: "https://evil.example/WSUM/show/4"),
            event(title: "Another station", url: "https://spinitron.com/OTHER/show/5")
        ]
        let data = try JSONSerialization.data(withJSONObject: rows)
        let shows = try WSUMShows.decode(data)
        XCTAssertEqual(shows.count, 1)
        XCTAssertTrue(shows[0].matches("WSUM books"))
        XCTAssertTrue(shows[0].matches("DJ Reader"))
        XCTAssertFalse(shows[0].matches("jazz orchestra"))
        XCTAssertTrue(shows[0].isOnAir(at: shows[0].startsAt))
        XCTAssertFalse(shows[0].isOnAir(at: shows[0].endsAt))
    }

    func testScheduleRequestHasRequiredRangeInMadisonTime() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-07T01:00:00Z"))
        let url = try XCTUnwrap(WSUMShows.feedURL(now: now))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "start" }?.value, "2026-09-06")
        XCTAssertEqual(items.first { $0.name == "end" }?.value, "2026-09-13")
    }

    @MainActor func testStationSavesSurviveRelaunchAndStayAccountScoped() throws {
        let suite = "RadioTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID(), other = UUID()
        let saved = SavedRadioStations(defaults: defaults)
        saved.activate(ownerID: owner)
        saved.toggle("wsum-fm")
        saved.toggle("https://untrusted.example/stream")
        XCTAssertEqual(saved.ids, ["wsum-fm"])
        saved.activate(ownerID: other)
        XCTAssertTrue(saved.ids.isEmpty)
        let restored = SavedRadioStations(defaults: defaults)
        restored.activate(ownerID: owner)
        XCTAssertEqual(restored.ids, ["wsum-fm"])
        restored.toggle("wsum-fm")
        XCTAssertTrue(restored.ids.isEmpty)
    }

    func testLyricsPreviewShowsContextWithoutInventingTiming() {
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: nil, count: 0)), [])
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: nil, count: 8)), [0, 1, 2])
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: 4, count: 8)), [3, 4, 5])
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: 7, count: 8)), [5, 6, 7])
    }

    func testPrivateMixtapeMediaReferencesCannotSelectOtherBucketsOrPaths() {
        let path = "\(UUID())/\(UUID())/\(UUID()).jpg"
        XCTAssertEqual(MixtapeMediaReference.path(from: "heartable-media://mixtape-gifts/\(path)"), path)
        XCTAssertNil(MixtapeMediaReference.path(from: "heartable-media://avatars/\(path)"))
        XCTAssertNil(MixtapeMediaReference.path(from: "heartable-media://mixtape-gifts/../../private"))
        XCTAssertNil(MixtapeMediaReference.path(from: "https://example.com/\(path)"))
    }

    private func event(title: String, url: String, kind: String = "spin-cal-show category-music") -> [String: String] {
        ["title": title, "text": "DJ Reader", "start": "2026-09-07T12:00:00-0500",
         "end": "2026-09-07T13:00:00-0500", "url": url, "className": kind]
    }
}
