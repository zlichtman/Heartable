import XCTest
@testable import Heartable

final class UnifiedTrackIdentityTests: XCTestCase {
    func testRemasterNoiseCollapsesAcrossProviders() {
        let spotify = UnifiedTrackIdentity.make(
            title: "Dreams - 2004 Remaster",
            artist: "Fleetwood Mac"
        )
        let apple = UnifiedTrackIdentity.make(
            title: "Dreams",
            artist: "Fleetwood Mac"
        )

        XCTAssertEqual(spotify, apple)
    }

    func testVersionDefiningQualifierRemainsDistinct() {
        let studio = UnifiedTrackIdentity.make(
            title: "Fast Car",
            artist: "Tracy Chapman"
        )
        let live = UnifiedTrackIdentity.make(
            title: "Fast Car (Live)",
            artist: "Tracy Chapman"
        )

        XCTAssertNotEqual(studio, live)
    }

    func testFeaturedArtistFormattingDoesNotSplitIdentity() {
        let first = UnifiedTrackIdentity.make(
            title: "Song (feat. Guest)",
            artist: "Primary Artist"
        )
        let second = UnifiedTrackIdentity.make(
            title: "Song",
            artist: "Primary Artist, Guest"
        )

        XCTAssertEqual(first, second)
    }
}
