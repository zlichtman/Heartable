import XCTest
@testable import Heartable

final class CSVImportParserTests: XCTestCase {
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
