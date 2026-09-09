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
        position: Int = 0,
        collectionID: String? = nil
    ) -> BackupInventoryItem {
        BackupInventoryItem(
            uri: uri,
            name: "Song",
            artist: "Artist",
            album: "Album",
            artworkURL: nil,
            collection: collection,
            position: position,
            collectionID: collectionID
        )
    }

    func testRenamingKnownPlaylistDoesNotCreateFalseTrackChanges() {
        let previous = item(uri: "spotify:track:one", collection: "Old name", collectionID: "playlist1")
        let current = item(uri: previous.uri, collection: "New name", collectionID: "playlist1")
        let diff = BackupSnapshotDiffer.difference(current: [current], previous: [previous])
        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
    }

    func testDistinctPlaylistsWithSameNameDoNotMerge() {
        let previous = item(uri: "spotify:track:one", collection: "Favorites", collectionID: "playlist1")
        let current = item(uri: previous.uri, collection: "Favorites", collectionID: "playlist2")
        let diff = BackupSnapshotDiffer.difference(current: [current], previous: [previous])
        XCTAssertEqual(diff.added, [current])
        XCTAssertEqual(diff.removed, [previous])
    }

    func testLegacySnapshotMatchesNewPlaylistIDsWithoutFalseChanges() {
        let legacy = item(uri: "apple:song:one", collection: "Road Trip")
        let current = item(uri: legacy.uri, collection: "Road Trip", collectionID: "newly-saved-id")
        let diff = BackupSnapshotDiffer.difference(current: [current], previous: [legacy])
        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
    }

    func testMissingServiceIsNotReportedAsMassDeletion() {
        let spotify = item(uri: "spotify:track:one", collection: "Road Trip")
        let apple = item(uri: "apple:song:one", collection: "Road Trip")
        let scope = BackupComparisonScope(current: [spotify], previous: [spotify, apple])
        XCTAssertEqual(scope.sharedProviders, [.spotify])
        XCTAssertEqual(scope.excludedProviders, [.apple])
        let diff = BackupSnapshotDiffer.difference(current: [spotify].filter(scope.includes),
                                                  previous: [spotify, apple].filter(scope.includes))
        XCTAssertTrue(diff.removed.isEmpty)
    }

    func testSamePlaylistNamesAcrossServicesKeepTheirProviderIdentity() {
        let spotify = item(uri: "spotify:track:one", collection: "Favorites", collectionID: "1")
        let apple = item(uri: "apple:song:one", collection: "Favorites", collectionID: "1")
        XCTAssertNotEqual(spotify.comparisonKey, apple.comparisonKey)
        XCTAssertEqual(spotify.providerID, .spotify)
        XCTAssertEqual(apple.providerID, .apple)
    }
}
