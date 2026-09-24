import XCTest
@testable import Heartable

final class BackupDetailTests: XCTestCase {
    private func playlist(tracks: Int = 2) -> SnapshotPlaylistDTO {
        SnapshotPlaylistDTO(id: UUID(), name: "Saved playlist", imageUrl: "https://example.com/cover.jpg", trackCount: tracks)
    }

    private func snapshot(playlists: Int = 2, tracks: Int = 4, liked: Int = 3) -> LibrarySnapshotDTO {
        LibrarySnapshotDTO(id: UUID(), playlistCount: playlists, trackCount: tracks, likedCount: liked)
    }

    func testAnEarlyReadCannotBeCachedAsACompleteBackup() {
        let saved = snapshot()
        let first = playlist()
        XCTAssertFalse(BackupDetail(playlists: [first], likedCount: 0).matches(saved))
        XCTAssertFalse(BackupDetail(playlists: [first, playlist()], likedCount: 0).matches(saved),
                       "Liked songs are inserted last; playlist completion alone is insufficient")
        XCTAssertTrue(BackupDetail(playlists: [first, playlist()], likedCount: 3).matches(saved),
                      "Retrying after the upload finishes accepts the complete contents")
    }

    func testCorrectPlaylistCountCannotHideWrongSongCounts() {
        XCTAssertFalse(BackupDetail(playlists: [playlist(), playlist(tracks: 1)], likedCount: 3).matches(snapshot()))
    }

    func testRepeatedRowsCannotStandInForMissingPlaylists() {
        let repeated = playlist()
        XCTAssertFalse(BackupDetail(playlists: [repeated, repeated], likedCount: 3).matches(snapshot()))
    }

    func testThirtyPlaylistsKeepTheirArtworkAndAreAllAvailable() {
        let playlists = (0..<30).map { _ in playlist(tracks: 100) }
        let detail = BackupDetail(playlists: playlists, likedCount: 259)
        XCTAssertTrue(detail.matches(snapshot(playlists: 30, tracks: 3_000, liked: 259)))
        XCTAssertEqual(detail.playlists.count, 30)
        XCTAssertTrue(detail.playlists.allSatisfy { $0.imageUrl != nil })
    }

    func testEmptyAndLikedOnlySnapshotsHaveValidDetails() {
        XCTAssertTrue(BackupDetail(playlists: [], likedCount: 0).matches(snapshot(playlists: 0, tracks: 0, liked: 0)))
        XCTAssertTrue(BackupDetail(playlists: [], likedCount: 5).matches(snapshot(playlists: 0, tracks: 0, liked: 5)))
    }

    func testLegacySnapshotsWithoutSummaryCountsStillOpen() {
        XCTAssertTrue(BackupDetail(playlists: [playlist()], likedCount: 4).matches(LibrarySnapshotDTO(id: UUID())))
    }
}
