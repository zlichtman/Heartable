import XCTest
@testable import Heartable

final class RadioRecordingMatcherTests: XCTestCase {
    @MainActor
    func testCacheOnlyReturnsConnectedRecordingAndKeepsVersionsSeparate() {
        let cache = RadioRecordingCache()
        cache.store(track(), for: spin)
        XCTAssertEqual(cache.match(spin, connected: [.spotify])?.key, "spotify:1")
        XCTAssertNil(cache.match(spin, connected: [.apple]))
        let live = WSUMSpin(id: "live", artist: spin.artist, song: "Halo (Live)", album: spin.album, time: "")
        XCTAssertNil(cache.match(live, connected: [.spotify]))
    }
    private let spin = WSUMSpin(id: "1", artist: "Beyoncé", song: "Halo", album: "Album", time: "10:00")
    private func track(name: String = "Halo", artist: String = "Beyonce", album: String = "Album") -> UnifiedTrack {
        .init(key: "spotify:1", providerID: .spotify, providerTrackID: "1", uri: "spotify:track:1",
              name: name, artists: [.init(id: "a", name: artist)], album: album, albumArt: nil, durationMs: 180000)
    }
    func testExactRecordingWithCaseAndDiacriticDifferencesMatches() {
        XCTAssertEqual(RadioRecordingMatcher.match(spin, in: [track(name: "HALO")])?.key, "spotify:1")
    }
    func testDoesNotSubstituteAnotherArtistOrVersion() {
        XCTAssertNil(RadioRecordingMatcher.match(spin, in: [track(artist: "Someone else")]))
        XCTAssertNil(RadioRecordingMatcher.match(spin, in: [track(name: "Halo (Live)")]))
        XCTAssertNil(RadioRecordingMatcher.match(spin, in: [track(album: "Live Album")]))
    }
    func testUnspecifiedAlbumAllowsExactTitleAndArtist() {
        let log = WSUMSpin(id: "2", artist: "Beyonce", song: "Halo", album: "", time: "")
        XCTAssertNotNil(RadioRecordingMatcher.match(log, in: [track()]))
    }
}
