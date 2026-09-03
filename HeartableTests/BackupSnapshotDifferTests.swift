import XCTest
@testable import Heartable

final class BackupSnapshotDifferTests: XCTestCase {
    func testDifferenceIncludesCollectionContext() {
        let song = item(uri: "spotify:track:one", collection: "Road Trip")
        let moved = item(uri: "spotify:track:one", collection: "Morning")

        let result = BackupSnapshotDiffer.difference(
            current: [moved],
            previous: [song]
        )

        XCTAssertEqual(result.added, [moved])
        XCTAssertEqual(result.removed, [song])
    }

    func testDifferencePreservesDuplicateOccurrences() {
        let first = item(uri: "apple:one", collection: "Liked Songs", position: 0)
        let duplicate = item(uri: "apple:one", collection: "Liked Songs", position: 1)

        let result = BackupSnapshotDiffer.difference(
            current: [first],
            previous: [first, duplicate]
        )

        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(result.removed, [duplicate])
    }

    func testComparisonIgnoresCollectionCaseAndDiacritics() {
        let current = item(uri: "spotify:track:two", collection: "Cafe")
        let previous = item(uri: "spotify:track:two", collection: "CAFÉ")

        let result = BackupSnapshotDiffer.difference(
            current: [current],
            previous: [previous]
        )

        XCTAssertTrue(result.added.isEmpty)
        XCTAssertTrue(result.removed.isEmpty)
    }

    private func item(
        uri: String,
        collection: String,
        position: Int = 0
    ) -> BackupInventoryItem {
        BackupInventoryItem(
            uri: uri,
            name: "Song",
            artist: "Artist",
            album: "Album",
            artworkURL: nil,
            collection: collection,
            position: position
        )
    }
}
