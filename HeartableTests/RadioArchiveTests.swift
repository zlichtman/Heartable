import XCTest
@testable import Heartable

final class RadioArchiveTests: XCTestCase {
    @MainActor func testProgramHeartsPersistAndStayAccountScoped() throws {
        let suite = "radio-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID()
        let saved = SavedRadioStations(defaults: defaults)
        let show = WSUMShow(id: "airing", title: "Any Radio Show", host: "A DJ", startsAt: .now,
                            endsAt: .now, pageURL: URL(string: "https://spinitron.com/WSUM/show/123/Show")!)
        saved.activate(ownerID: owner)
        saved.toggle(show.favoriteID)
        XCTAssertTrue(saved.contains(show.favoriteID))
        saved.activate(ownerID: UUID())
        XCTAssertFalse(saved.contains(show.favoriteID))
        saved.activate(ownerID: owner)
        XCTAssertTrue(saved.contains(show.favoriteID))
        saved.toggle(show.favoriteID)
        XCTAssertFalse(saved.contains(show.favoriteID))
    }

    func testBroadcastsDecodeNativeWeeklyHistory() throws {
        let html = #"<div class="playlist-list"><div class="list-item" data-key="22951874"><a href="https://spinitron.com/WSUM/pl/22951874/Sam-s-Jams?layout=1"><p class="timeslot">Aug 31, 2026 5:00 PM&nbsp;–&nbsp;6:00 PM</p></a></div><div class="list-item" data-key="2"><a href="https://evil.example/WSUM/pl/2"><p class="timeslot">Bad</p></a></div></div>"#
        let result = try WSUMArchive.broadcasts(html)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "22951874")
        XCTAssertEqual(result.first?.title, "Aug 31, 2026 5:00 PM – 6:00 PM")
    }

    func testSpinsDecodeEntitiesWithoutExternalNavigation() throws {
        let html = #"<div class="public-spins"><tr id="sp-123" data-spin="{&quot;a&quot;:&quot;Able Baker&quot;,&quot;s&quot;:&quot;You&#039;re On&quot;,&quot;r&quot;:&quot;Fall Through Sparks&quot;}"><td class="spin-time"><a>5:09 PM</a></td></tr></div>"#
        let result = try WSUMArchive.spins(html)
        XCTAssertEqual(result.first?.song, "You're On")
        XCTAssertEqual(result.first?.artist, "Able Baker")
        XCTAssertEqual(result.first?.time, "5:09 PM")
        XCTAssertThrowsError(try WSUMArchive.spins("<html>maintenance</html>"))
    }

    func testFavoriteIdentitySurvivesNextWeeksAiring() throws {
        let url = try XCTUnwrap(URL(string: "https://spinitron.com/WSUM/show/308292/Sam-s-Jams"))
        let a = WSUMShow(id: "first", title: "Sam's Jams", host: "Sam", startsAt: .now, endsAt: .now, pageURL: url)
        let b = WSUMShow(id: "second", title: "Sam's Jams", host: "Sam", startsAt: .distantFuture, endsAt: .distantFuture, pageURL: url)
        XCTAssertTrue(a.favoriteID.hasPrefix("wsum-program-"))
        XCTAssertEqual(a.favoriteID, b.favoriteID)
    }

    func testSpotifyMalformedPageIsNotAnEmptyLibrary() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(Paged<SpotifyTrack>.self, from: Data("{}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Paged<SpotifyTrack>.self, from: Data("{\"items\":null}".utf8)))
        let empty = try JSONDecoder().decode(Paged<SpotifyTrack>.self, from: Data("{\"items\":[],\"next\":null}".utf8))
        XCTAssertEqual(empty.items?.count, 0)
    }

    func testSpotifyCurrentAndLegacyPlaylistCounts() throws {
        for key in ["items", "tracks"] {
            let data = Data("{\"id\":\"p\",\"name\":\"Music\",\"\(key)\":{\"total\":42}}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(SpotifyPlaylist.self, from: data).tracks?.total, 42)
        }
    }
}
