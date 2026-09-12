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

    /// A relaunch must not forget Spotify's cooldown and start a fresh burst.
    func testCooldownSurvivesRelaunchWhenPersisted() async {
        let suite = "SpotifyReadBackoffTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let first = SpotifyReadBackoff(persisting: true, suiteName: suite)
        _ = await first.record("600", now: now)
        // A new process reads the same store.
        let relaunched = SpotifyReadBackoff(persisting: true, suiteName: suite)
        let remaining = await relaunched.remaining(now: now.addingTimeInterval(100))
        XCTAssertEqual(remaining, 500)
        let resume = await relaunched.resumeDate(now: now.addingTimeInterval(100))
        XCTAssertEqual(resume, now.addingTimeInterval(600))
        let expired = await relaunched.remaining(now: now.addingTimeInterval(601))
        XCTAssertNil(expired)
        // Unpersisted instances stay isolated, as the existing tests rely on.
        let isolated = await SpotifyReadBackoff().remaining(now: now)
        XCTAssertNil(isolated)
    }

    /// Spotify returns `null` rows for playlists/tracks it can no longer resolve.
    /// One such row must not turn a whole page into an unavailable read.
    func testPagedDecodeSkipsNullRowsInsteadOfFailingThePage() throws {
        let json = """
        {"items":[null,{"id":"1","uri":"spotify:track:1","name":"Kept"},null],"next":null}
        """
        let page = try JSONDecoder().decode(Paged<SpotifyTrack>.self, from: Data(json.utf8))
        XCTAssertEqual(page.items?.map(\.id), ["1"])
        XCTAssertNil(page.next)
        // A missing `items` key is still an error, never an empty library.
        XCTAssertThrowsError(try JSONDecoder().decode(Paged<SpotifyTrack>.self, from: Data("{\"next\":null}".utf8)))
    }
}

private actor ReadSequence {
    var reads: [ProviderRead<UnifiedTrack>]
    init(_ reads: [ProviderRead<UnifiedTrack>]) { self.reads = reads }
    func next() -> ProviderRead<UnifiedTrack> { reads.isEmpty ? .unavailable : reads.removeFirst() }
}
