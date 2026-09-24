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
        XCTAssertEqual(ProviderCatalog.entry(.radioBrowser)?.section, .discovery)
        if ProviderCatalog.entry(.lastfm)?.status == .live {
            XCTAssertEqual(ProviderCatalog.entry(.lastfm)?.section, .history)
        }
        XCTAssertEqual(ProviderCatalog.entry(.wsum)?.section, .discovery)
        XCTAssertEqual(ProviderCatalog.entries(in: .library).map(\.id), [.apple, .spotify, .plex, .jellyfin])
        XCTAssertEqual(ProviderCatalog.searchableLibraryIDs, [.apple, .spotify, .plex, .jellyfin])
        XCTAssertNil(ProviderCatalog.entry(.internetArchive))
    }

    func testWSUMSearchIsSpecificAndStable() {
        XCTAssertEqual(FeaturedRadioStations.search("WSUM").count, 3)
        XCTAssertEqual(FeaturedRadioStations.search(" wsum sports ").first?.name, "WSUM Sports")
        XCTAssertEqual(FeaturedRadioStations.search("91.7").first?.providerTrackID, "wsum-fm")
        XCTAssertTrue(FeaturedRadioStations.search("unknown artist").isEmpty)
        XCTAssertTrue(FeaturedRadioStations.search("  ").isEmpty)
        XCTAssertNil(FeaturedRadioStations.station(id: "https://untrusted.example/stream"))
        XCTAssertEqual(Set(FeaturedRadioStations.all.map(\.id)).count, FeaturedRadioStations.all.count)
        XCTAssertEqual(FeaturedRadioStations.search("Seattle").first?.providerTrackID, "kexp")
        XCTAssertEqual(FeaturedRadioStations.search("WFMU").first?.providerID, .radioBrowser)
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
        for id in [ProviderID.wsum, .radioBrowser, .audius, .deezer] {
            let entry = ProviderCatalog.entry(id)!
            XCTAssertFalse(entry.requiresAccountConnection)
            XCTAssertFalse(entry.capabilities.contains(.top))
            XCTAssertFalse(entry.capabilities.contains(.search))
            let provider = ProviderRegistry.provider(for: id)
            let available = await provider.isConnected()
            let personalTop = await provider.topTracks(range: .longTerm, limit: 25)
            XCTAssertTrue(available)
            XCTAssertTrue(personalTop.isEmpty)
        }
    }

    func testSearchDefaultsToConnectedLibrariesAndFirstTapDeselects() {
        var scope = LibrarySearchScope()
        let connected: Set<ProviderID> = [.spotify, .apple]
        XCTAssertEqual(scope.resolved(connected: connected), connected)
        scope.toggle(.spotify, connected: connected)
        XCTAssertEqual(scope.resolved(connected: connected), [.apple])
        scope.toggle(.apple, connected: connected)
        XCTAssertTrue(scope.resolved(connected: connected).isEmpty)
        scope.toggle(.spotify, connected: connected)
        XCTAssertEqual(scope.resolved(connected: connected), [.spotify])
        XCTAssertTrue(scope.resolved(connected: []).isEmpty)
    }

    func testUnsupportedAndDisconnectedSearchChoicesCannotBeSelected() {
        var scope = LibrarySearchScope()
        let connected: Set<ProviderID> = [.spotify, .lastfm, .audius, .wsum]
        for id in [ProviderID.deezer, .audius, .wsum, .heartable, .lastfm, .apple] {
            scope.toggle(id, connected: connected)
        }
        XCTAssertEqual(scope.resolved(connected: connected), [.spotify])
        scope.selection = [.spotify, .deezer, .apple]
        XCTAssertEqual(scope.resolved(connected: connected), [.spotify])
    }

    func testSearchMenuContainsOnlyConnectedLibrariesWithoutDuplicates() {
        let choices = LibrarySearchScope.selectableProviders(connected: [.apple, .spotify, .apple, .heartable, .wsum, .audius, .deezer, .lastfm])
        XCTAssertEqual(choices, [.apple, .spotify])
        XCTAssertTrue(LibrarySearchScope.selectableProviders(connected: []).isEmpty)
    }

    func testRadioTracksKeepCanonicalIdentityAndHttpsStreams() {
        for station in FeaturedRadioStations.all {
            XCTAssertEqual(station.stream.scheme, "https")
            XCTAssertTrue(station.track.providerID.isLiveRadio)
            XCTAssertEqual(station.track.durationMs, 0)
        }
        XCTAssertEqual(FeaturedRadioStations.station(id: "wsum-fm")?.track.uri, "wsum:track:wsum-fm")
    }

    func testRadioRejectsUnknownAndMismatchedStationIdentity() async {
        let provider = RadioProvider(id: .wsum)
        let track = FeaturedRadioStations.station(id: "kexp")!.track
        do {
            try await provider.play(track)
            XCTFail("A provider cannot reinterpret another station's identity")
        } catch { XCTAssertTrue(error is ProviderError) }
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
        for id in [ProviderID.apple, .spotify, .plex, .jellyfin, .wsum] {
            XCTAssertNotNil(UIImage(named: ProviderLogo.assetName(for: id, heartableIconKey: "core")))
        }
    }
}
