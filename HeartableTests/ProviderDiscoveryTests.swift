import XCTest
import UIKit
@testable import Heartable

final class ProviderDiscoveryTests: XCTestCase {
    func testUnsupportedServicesNeverAppearAsConnectableLibraries() {
        for entry in ProviderCatalog.all where entry.status != .live {
            XCTAssertEqual(entry.section, .comingSoon)
        }
        XCTAssertEqual(ProviderCatalog.entry(.spotify)?.section, .library)
        XCTAssertEqual(ProviderCatalog.entry(.apple)?.section, .library)
        XCTAssertNil(ProviderCatalog.entry(.listenbrainz))
        XCTAssertNil(ProviderCatalog.entry(.mixcloud))
        XCTAssertNil(ProviderCatalog.entry(.radioBrowser))
        if ProviderCatalog.entry(.lastfm)?.status == .live {
            XCTAssertEqual(ProviderCatalog.entry(.lastfm)?.section, .history)
        }
        XCTAssertEqual(ProviderCatalog.entry(.wsum)?.section, .discovery)
        XCTAssertEqual(ProviderCatalog.entries(in: .library).map(\.id), [.apple, .spotify, .plex, .jellyfin])
        XCTAssertEqual(ProviderCatalog.publicSearchIDs, [.audius, .deezer, .wsum])
        XCTAssertNil(ProviderCatalog.entry(.internetArchive))
    }

    func testWSUMSearchIsSpecificAndStable() {
        XCTAssertEqual(FeaturedRadioStations.search("WSUM").count, 3)
        XCTAssertEqual(FeaturedRadioStations.search(" wsum sports ").first?.name, "WSUM Sports")
        XCTAssertEqual(FeaturedRadioStations.search("91.7").first?.providerTrackID, "wsum-fm")
        XCTAssertTrue(FeaturedRadioStations.search("unknown artist").isEmpty)
        XCTAssertTrue(FeaturedRadioStations.search("  ").isEmpty)
        XCTAssertNil(FeaturedRadioStations.station(id: "https://untrusted.example/stream"))
        XCTAssertEqual(Set(FeaturedRadioStations.all.map(\.id)).count, 3)
    }

    func testRadioListeningDoesNotInventSongPlayCounts() {
        var tracker = ListeningSessionTracker()
        let start = Date(timeIntervalSince1970: 0)
        for second in stride(from: 0, through: 120, by: 5) {
            let now = PlayerStore.Now(
                source: .wsum, name: "WSUM 91.7 FM", artist: "WSUM",
                artworkURL: nil, isPlaying: true, positionMs: second * 1_000,
                durationMs: 0, uri: "wsum:track:wsum-fm", providerTrackID: "wsum-fm"
            )
            XCTAssertFalse(tracker.observe(now: now, ghost: false, at: start.addingTimeInterval(Double(second))))
        }
    }

    func testPublicSourcesNeverBecomeAccountConnectionsOrPersonalStats() async {
        for id in ProviderCatalog.publicSearchIDs {
            let entry = ProviderCatalog.entry(id)!
            XCTAssertFalse(entry.requiresAccountConnection)
            XCTAssertFalse(entry.capabilities.contains(.top))
            let provider = ProviderRegistry.provider(for: id)
            let available = await provider.isConnected()
            let personalTop = await provider.topTracks(range: .longTerm, limit: 25)
            XCTAssertTrue(available)
            XCTAssertTrue(personalTop.isEmpty)
        }
    }

    func testSearchAllIncludesRadioAndSupportsExplicitMultiSelection() {
        var scope = LibrarySearchScope()
        let connected: Set<ProviderID> = [.spotify, .apple]
        XCTAssertEqual(scope.resolved(connected: connected), Set(ProviderCatalog.publicSearchIDs).union([.heartable, .spotify, .apple]))
        scope.toggle(.wsum, connected: connected)
        XCTAssertEqual(scope.resolved(connected: connected), [.wsum])
        scope.toggle(.audius, connected: connected)
        XCTAssertEqual(scope.resolved(connected: connected), [.wsum, .audius])
        scope.toggle(.apple, connected: connected)
        XCTAssertTrue(scope.resolved(connected: connected).contains(.apple))
        scope.toggle(.apple, connected: connected)
        XCTAssertFalse(scope.resolved(connected: connected).contains(.apple))
        XCTAssertEqual(scope.resolved(connected: []), [.wsum, .audius])
        scope.selection = []
        XCTAssertTrue(scope.resolved(connected: connected).isEmpty)
        scope.selection = nil
        XCTAssertTrue(scope.resolved(connected: connected).contains(.wsum))
    }

    @MainActor
    func testSearchHasFiveCategoriesAfterTheTypeSelector() {
        XCTAssertEqual(LibrarySearchResultType.allCases.filter { $0 != .all }.map(\.rawValue),
                       ["Songs", "Playlists", "Artists", "Profiles", "Stations"])
    }

    @MainActor
    func testProviderMenuUsesInstalledHeartableIconAndRealServiceAssets() {
        for choice in AppIconCatalog.choices {
            XCTAssertEqual(ProviderLogo.assetName(for: .heartable, heartableIconKey: choice.id), choice.previewAssetName)
        }
        for id in [.apple, .spotify, .plex, .jellyfin] + ProviderCatalog.publicSearchIDs {
            XCTAssertNotNil(UIImage(named: ProviderLogo.assetName(for: id, heartableIconKey: "core")))
        }
    }
}
