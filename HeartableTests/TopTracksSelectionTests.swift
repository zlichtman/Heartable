import XCTest
@testable import Heartable

final class TopTracksSelectionTests: XCTestCase {
    private let connected: [TopTracksSource] = [.heartable, .spotify]

    func testFreshAccountStartsWithSpotifyInsteadOfAnEmptyHeartableRanking() {
        var selection = TopTracksSelection()
        selection.resolve(availableSources: connected, populatedSources: [])
        XCTAssertEqual(selection.source, .spotify)
        XCTAssertNil(selection.explicitSource)
    }

    func testSpotifyWinsWhenBothSourcesHaveCachedStatsOnFirstOpen() {
        var selection = TopTracksSelection()
        selection.resolve(availableSources: connected, populatedSources: [.heartable, .spotify])
        XCTAssertEqual(selection.source, .spotify)
    }

    func testCachedContentCanPaintWithoutWaitingForAnotherSource() {
        var selection = TopTracksSelection()
        selection.resolve(availableSources: connected, populatedSources: [.heartable])
        XCTAssertEqual(selection.source, .heartable)
    }

    func testAnEmptySpotifyRankingFallsBackToRealHeartableStats() {
        var selection = TopTracksSelection()
        selection.resolve(availableSources: connected, populatedSources: [])
        selection.resolve(availableSources: connected, populatedSources: [.heartable])
        XCTAssertEqual(selection.source, .heartable)
    }

    func testExplicitHeartableSelectionIsNotOverriddenEvenWhenEmpty() {
        var selection = TopTracksSelection()
        selection.select(.heartable)
        selection.resolve(availableSources: connected, populatedSources: [.spotify])
        XCTAssertEqual(selection.source, .heartable)
        XCTAssertEqual(selection.explicitSource, .heartable)
    }

    func testExplicitSpotifySelectionIsNotOverriddenEvenWhenEmpty() {
        var selection = TopTracksSelection()
        selection.select(.spotify)
        selection.resolve(availableSources: connected, populatedSources: [.heartable])
        XCTAssertEqual(selection.source, .spotify)
    }

    func testRefreshDoesNotReplaceAlreadyUsefulContent() {
        var selection = TopTracksSelection()
        selection.resolve(availableSources: connected, populatedSources: [.heartable])
        selection.resolve(availableSources: connected, populatedSources: [.heartable, .spotify])
        XCTAssertEqual(selection.source, .heartable)
    }

    func testDisconnectDropsAnUnavailableManualSource() {
        var selection = TopTracksSelection()
        selection.select(.spotify)
        selection.resolve(availableSources: [.heartable], populatedSources: [.spotify])
        XCTAssertEqual(selection.source, .heartable)
        XCTAssertNil(selection.explicitSource)
    }

    func testProviderRestorationCanUpgradeAnEmptyAutomaticSelection() {
        var selection = TopTracksSelection()
        selection.resolve(availableSources: [.heartable], populatedSources: [])
        selection.resolve(availableSources: connected, populatedSources: [])
        XCTAssertEqual(selection.source, .spotify)
    }

    func testUnsupportedAndDuplicateSourcesNeverBecomeFallbacks() {
        XCTAssertEqual(
            TopTracksSelection.preferredOrder([.apple, .spotify, .spotify, .heartable]),
            [.spotify, .heartable]
        )
        var selection = TopTracksSelection()
        selection.resolve(availableSources: [.heartable, .apple], populatedSources: [.apple])
        XCTAssertEqual(selection.source, .heartable)
    }
}
