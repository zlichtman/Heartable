import XCTest
@testable import Heartable

final class ProviderDiscoveryTests: XCTestCase {
    func testUnsupportedServicesNeverAppearAsConnectableLibraries() {
        for entry in ProviderCatalog.all where entry.status != .live {
            XCTAssertEqual(entry.section, .comingSoon)
        }
        XCTAssertEqual(ProviderCatalog.entry(.spotify)?.section, .library)
        XCTAssertEqual(ProviderCatalog.entry(.apple)?.section, .library)
        XCTAssertEqual(ProviderCatalog.entry(.listenbrainz)?.section, .history)
        if ProviderCatalog.entry(.lastfm)?.status == .live {
            XCTAssertEqual(ProviderCatalog.entry(.lastfm)?.section, .history)
        }
        XCTAssertEqual(ProviderCatalog.entry(.radioBrowser)?.section, .discovery)
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
                source: .radioBrowser, name: "WSUM 91.7 FM", artist: "WSUM",
                artworkURL: nil, isPlaying: true, positionMs: second * 1_000,
                durationMs: 0, uri: "radio_browser:track:wsum-fm", providerTrackID: "wsum-fm"
            )
            XCTAssertFalse(tracker.observe(now: now, ghost: false, at: start.addingTimeInterval(Double(second))))
        }
    }
}
