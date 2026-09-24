import XCTest
@testable import Heartable

final class BackupArtworkTests: XCTestCase {
    private let albumURL = URL(string: "https://example.com/album.jpg")!
    private let playlistURL = URL(string: "https://example.com/playlist.jpg")!

    private func track() -> UnifiedTrack {
        UnifiedTrack(key: "apple:123", providerID: .apple, providerTrackID: "123",
                     uri: "apple:track:123", name: "Song",
                     artists: [UnifiedArtist(id: "artist", name: "Artist")],
                     album: "Album", albumArt: albumURL, durationMs: 123_000)
    }

    func testLiveCapturePreservesPlaylistAndTrackArtwork() {
        let playlist = UnifiedPlaylist(
            key: "apple:playlist", providerID: .apple, playlistID: "playlist",
            name: "Favorites", description: nil, image: playlistURL, trackCount: 1, owner: nil
        )
        let capture = CapturedPlaylist(playlist: playlist, tracks: [track()])
        XCTAssertEqual(capture.imageURL, playlistURL.absoluteString)
        XCTAssertEqual(capture.sourceID, "playlist")
        XCTAssertEqual(capture.rows.first?.albumArtURL, albumURL.absoluteString)
        XCTAssertEqual(capture.rows.first?.durationMS, 123_000)
    }

    func testArtworkSurvivesCSVExportAndImport() {
        let csv = CSVDocument.csv(from: [CSVDocument.Row(
            playlist: "Favorites, forever", name: "Song", artist: "Artist", album: "Album",
            uri: "apple:track:123", albumArtURL: albumURL.absoluteString,
            playlistImageURL: playlistURL.absoluteString, durationMS: 123_000
        )])
        let rows = CSVImportParser.parse(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.uri, "apple:track:123")
        XCTAssertEqual(rows.first?.albumArtURL, albumURL.absoluteString)
        XCTAssertEqual(rows.first?.durationMS, 123_000)
        XCTAssertEqual(CapturedPlaylist(name: "Favorites", rows: rows).imageURL, playlistURL.absoluteString)
    }

    func testSnapshotPayloadsEncodeExistingArtworkColumns() throws {
        func json<T: Encodable>(_ value: T) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        }
        let playlist = try json(SnapshotPlaylistInsertDTO(
            snapshotId: UUID(), name: "Favorites", trackCount: 1, imageUrl: playlistURL.absoluteString
        ))
        let track = try json(SnapshotTrackInsertDTO(
            snapshotPlaylistId: UUID(), spotifyTrackUri: "apple:track:123", trackName: "Song",
            artistName: "Artist", albumName: "Album", position: 0,
            albumArtUrl: albumURL.absoluteString, durationMs: 123_000
        ))
        let liked = try json(SnapshotLikedTrackInsertDTO(
            snapshotId: UUID(), spotifyTrackUri: "apple:track:123", trackName: "Song",
            artistName: "Artist", albumName: "Album", position: 0,
            albumArtUrl: albumURL.absoluteString, durationMs: 123_000
        ))
        XCTAssertEqual(playlist["image_url"] as? String, playlistURL.absoluteString)
        for row in [track, liked] {
            XCTAssertEqual(row["album_art_url"] as? String, albumURL.absoluteString)
            XCTAssertEqual(row["duration_ms"] as? Int, 123_000)
        }
    }
}
