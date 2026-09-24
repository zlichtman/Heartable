import XCTest
@testable import Heartable

final class CSVImportParserTests: XCTestCase {
    func testOriginalSnapshotDateSurvivesCSVExport() throws {
        let date = "2024-01-02T03:04:05.123Z"
        let csv = CSVDocument.csv(from: [.init(playlist: "Old", name: "Song", artist: "Artist", album: nil,
                                             uri: "spotify:track:123", albumArtURL: nil,
                                             playlistImageURL: nil, durationMS: nil)], createdAt: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(try CSVImportParser.snapshotDate(csv), formatter.date(from: date))
    }

    func testLegacyCSVDoesNotGuessDateFromTrackAddedDate() throws {
        XCTAssertNil(try CSVImportParser.snapshotDate("name,artist,added_at\nSong,Artist,2024-01-02T03:04:05Z"))
    }

    func testInvalidAndConflictingSnapshotDatesAreRejected() {
        XCTAssertThrowsError(try CSVImportParser.snapshotDate("snapshot_created_at\ninvalid"))
        XCTAssertThrowsError(try CSVImportParser.snapshotDate("snapshot_created_at\n2024-01-02T03:04:05Z\n2025-01-02T03:04:05Z"))
    }

    func testParsesQuotedCommasAndEscapedQuotes() {
        let csv = """
        playlist,name,artist,album,uri
        "Favorites, 2026","A ""Quoted"" Song",Artist,Album,spotify:track:1234567890123456789012
        """

        let rows = CSVImportParser.parse(csv)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].playlist, "Favorites, 2026")
        XCTAssertEqual(rows[0].name, "A \"Quoted\" Song")
    }

    func testAcceptsSpotifyURLAndSemicolonDelimiter() {
        let csv = """
        playlist;track name;artist;spotify url
        Road Trip;Song;Artist;https://open.spotify.com/track/1234567890123456789012?si=test
        """

        let rows = CSVImportParser.parse(csv)

        XCTAssertEqual(rows.first?.uri, "spotify:track:1234567890123456789012")
    }

    func testRejectsRowsWithoutTrackReference() {
        let csv = """
        playlist,name,artist
        Favorites,Song,Artist
        """

        XCTAssertTrue(CSVImportParser.parse(csv).isEmpty)
    }
}
