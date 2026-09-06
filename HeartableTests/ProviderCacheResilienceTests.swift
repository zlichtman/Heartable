import XCTest
@testable import Heartable

final class ProviderCacheResilienceTests: XCTestCase {
    private func playlist(_ id: ProviderID, name: String = "Saved", count: Int = 1) -> UnifiedPlaylist {
        .init(key: id.rawValue + ":p", providerID: id, playlistID: "p", name: name,
              description: nil, image: nil, trackCount: count, owner: nil, contentRevision: "v1")
    }

    func testRateLimitedSpotifySurvivesSuccessfulAppleRefresh() {
        let spotify = playlist(.spotify)
        let apple = playlist(.apple, name: "Old Apple")
        let fresh = playlist(.apple, name: "New Apple")
        let merged = ProviderCacheMerge.merge(cached: [spotify, apple], providers: [.apple, .spotify],
                                             reads: [.apple: .success([fresh]), .spotify: .unavailable],
                                             providerID: { $0.providerID })
        XCTAssertEqual(merged, [fresh, spotify])
    }

    func testAuthoritativeEmptyClearsOnlyThatProvider() {
        let spotify = playlist(.spotify)
        let apple = playlist(.apple)
        let merged = ProviderCacheMerge.merge(cached: [spotify, apple], providers: [.spotify, .apple],
                                             reads: [.spotify: .success([]), .apple: .unavailable],
                                             providerID: { $0.providerID })
        XCTAssertEqual(merged, [apple])
    }

    func testExplicitDisconnectStillRemovesOnlyThatProvider() {
        let spotify = playlist(.spotify)
        let merged = ProviderCacheMerge.merge(cached: [spotify, playlist(.apple)], providers: [.spotify],
                                             reads: [.spotify: .unavailable], providerID: { $0.providerID })
        XCTAssertEqual(merged, [spotify])
    }

    @MainActor func testFailedPlaylistRefreshPreservesOrderURIsAndRetryState() async {
        func track(_ id: String) -> UnifiedTrack {
            .init(key: "spotify:\(id)", providerID: .spotify, providerTrackID: id,
                  uri: "spotify:track:\(id)", name: "Saved song \(id)", artists: [],
                  album: nil, albumArt: nil, durationMs: 180_000)
        }
        let first = track("one")
        let second = track("two")
        let source = ReadSequence([.success([first, second, first]), .unavailable, .success([])])
        let repo = PlaylistTracksRepository(fetch: { _ in await source.next() }, persistenceEnabled: false)
        let playlist = playlist(.spotify)
        await repo.load(playlist)
        await repo.load(playlist, force: true)
        XCTAssertEqual(repo.tracks(for: playlist).map(\.uri), [first.uri, second.uri, first.uri])
        XCTAssertTrue(repo.hasResolved(playlist))
        XCTAssertTrue(repo.didFail(playlist))
        XCTAssertFalse(repo.isInitiallyLoading(playlist))
        await repo.load(playlist, force: true)
        XCTAssertTrue(repo.tracks(for: playlist).isEmpty)
        XCTAssertFalse(repo.didFail(playlist))
    }

    func testCooldownHonorsLongRetryAfterWithoutSleepingOrShorteningIt() async {
        let gate = SpotifyReadBackoff()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let delay = await gate.record("3600", now: now)
        XCTAssertEqual(delay, 3600)
        _ = await gate.record("5", now: now.addingTimeInterval(10))
        let remaining = await gate.remaining(now: now.addingTimeInterval(20))
        XCTAssertEqual(remaining, 3580)
        let expired = await gate.remaining(now: now.addingTimeInterval(3600))
        XCTAssertNil(expired)
    }
}

private actor ReadSequence {
    var reads: [ProviderRead<UnifiedTrack>]
    init(_ reads: [ProviderRead<UnifiedTrack>]) { self.reads = reads }
    func next() -> ProviderRead<UnifiedTrack> { reads.isEmpty ? .unavailable : reads.removeFirst() }
}
