import XCTest
@testable import Heartable

final class WeeklyRecapTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testCurrentWeekUsesMondayBoundaryAndRealPlayRowsOnly() {
        let now = date("2026-07-22T12:00:00Z")
        let entries = [
            play(
                id: "00000000-0000-0000-0000-000000000001",
                uri: "spotify:track:a",
                title: "Pink Moon",
                artist: "Nick Drake",
                durationMs: 120_000,
                at: "2026-07-20T00:00:00Z"
            ),
            play(
                id: "00000000-0000-0000-0000-000000000002",
                uri: "spotify:track:b",
                title: "Before Monday",
                artist: "Someone",
                durationMs: 300_000,
                at: "2026-07-19T23:59:59Z"
            ),
            play(
                id: "00000000-0000-0000-0000-000000000003",
                uri: "spotify:track:c",
                title: "Broken timestamp",
                artist: "Someone",
                durationMs: 300_000,
                at: "not-a-date"
            ),
        ]

        let collection = WeeklyRecapBuilder.makeCollection(
            entries: entries,
            now: now,
            calendar: WeeklyRecapBuilder.recapCalendar(timeZone: utc)
        )

        XCTAssertEqual(
            collection.current.weekStart,
            date("2026-07-20T00:00:00Z")
        )
        XCTAssertEqual(collection.current.playCount, 1)
        XCTAssertEqual(
            collection.current.estimatedListeningMilliseconds,
            120_000
        )
        XCTAssertEqual(collection.completed.count, 1)
        XCTAssertEqual(collection.completed[0].playCount, 1)
    }

    func testCrossProviderCopiesRollIntoOneTrackAndArtist() {
        let interval = DateInterval(
            start: date("2026-07-20T00:00:00Z"),
            end: date("2026-07-27T00:00:00Z")
        )
        let entries = [
            play(
                id: "00000000-0000-0000-0000-000000000011",
                uri: "spotify:track:one",
                title: "Song (Remastered 2020)",
                artist: "Artist feat. Guest",
                durationMs: 180_000,
                at: "2026-07-21T12:00:00Z"
            ),
            play(
                id: "00000000-0000-0000-0000-000000000012",
                uri: "apple:track:two",
                title: "Song",
                artist: "Artist",
                durationMs: 181_000,
                at: "2026-07-22T12:00:00Z"
            ),
        ]

        let recap = WeeklyRecapBuilder.make(
            entries: entries,
            interval: interval,
            generatedAt: interval.end
        )

        XCTAssertEqual(recap.playCount, 2)
        XCTAssertEqual(recap.uniqueTrackCount, 1)
        XCTAssertEqual(recap.uniqueArtistCount, 1)
        XCTAssertEqual(recap.topTracks.first?.playCount, 2)
        XCTAssertEqual(recap.topArtists.first?.playCount, 2)
        XCTAssertEqual(recap.estimatedListeningMilliseconds, 361_000)
    }

    func testRankingUsesPlayCountThenRecencyAndNeverInventsDuration() {
        let interval = DateInterval(
            start: date("2026-07-20T00:00:00Z"),
            end: date("2026-07-27T00:00:00Z")
        )
        let entries = [
            play(
                id: "00000000-0000-0000-0000-000000000021",
                uri: "spotify:track:a",
                title: "Older",
                artist: "Artist A",
                durationMs: nil,
                at: "2026-07-21T12:00:00Z"
            ),
            play(
                id: "00000000-0000-0000-0000-000000000022",
                uri: "spotify:track:b",
                title: "Newer",
                artist: "Artist B",
                durationMs: -1,
                at: "2026-07-22T12:00:00Z"
            ),
        ]

        let recap = WeeklyRecapBuilder.make(
            entries: entries,
            interval: interval
        )

        XCTAssertEqual(recap.topTracks.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(recap.estimatedListeningMilliseconds, 0)
    }

    func testArchiveCacheFilenamesAreAccountScoped() {
        let first = UUID()
        let second = UUID()
        XCTAssertNotEqual(
            WeeklyRecapArchiveStore.cacheURL(ownerID: first),
            WeeklyRecapArchiveStore.cacheURL(ownerID: second)
        )
    }

    private func play(
        id: String,
        uri: String,
        title: String,
        artist: String,
        durationMs: Int?,
        at playedAt: String
    ) -> PlayEntryDTO {
        PlayEntryDTO(
            id: UUID(uuidString: id)!,
            trackUri: uri,
            trackName: title,
            artist: artist,
            durationMs: durationMs,
            playedAt: playedAt,
            albumArt: nil
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
