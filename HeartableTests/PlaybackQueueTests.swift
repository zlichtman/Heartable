import XCTest
@testable import Heartable

final class PlaybackQueueTests: XCTestCase {
    func testInOrderStartsAtTappedOccurrenceAndKeepsNextSongs() {
        let tracks = (0..<5).map { track(String($0)) }
        var queue = PlaybackQueue(tracks: tracks, startingAt: 2)
        XCTAssertEqual(queue.current, tracks[2])
        XCTAssertEqual(queue.providerSegment, Array(tracks[2...]))
        queue.next()
        XCTAssertEqual(queue.current, tracks[3])
        queue.previous()
        XCTAssertEqual(queue.current, tracks[2])
    }

    func testBothShuffleModesBuildEntireQueueWithTappedSongFirst() {
        let tracks = (0..<60).map { track(String($0)) }
        for mode in [ShuffleMode.shuffle, .weighted] {
            let queue = PlaybackQueue(tracks: tracks, startingAt: 17, mode: mode,
                                      weights: [tracks[0].uri: 100])
            XCTAssertEqual(queue.current, tracks[17])
            XCTAssertEqual(queue.entries.count, tracks.count)
            XCTAssertEqual(Set(queue.entries.map(\.id)), Set(tracks.indices))
            XCTAssertEqual(queue.providerSegment.count, tracks.count)
        }
    }

    func testDuplicateSongsRemainSeparateQueueEntries() {
        let song = track("same")
        var queue = PlaybackQueue(tracks: [song, song, track("last")])
        XCTAssertEqual(queue.entries.map(\.id), [0, 1, 2])
        queue.observe(uri: song.uri)
        XCTAssertEqual(queue.index, 0, "Repeated polls must not skip duplicates")
        queue.observe(uri: song.uri, newOccurrence: true)
        XCTAssertEqual(queue.index, 1)
        queue.next()
        XCTAssertEqual(queue.current?.providerTrackID, "last")
    }

    func testNativeQueueStopsAtProviderBoundaryWithoutDroppingRemainder() {
        let tracks = [track("a"), track("b"), track("c", .apple), track("d")]
        var queue = PlaybackQueue(tracks: tracks)
        XCTAssertEqual(queue.providerSegment, Array(tracks.prefix(2)))
        queue.next()
        queue.next()
        XCTAssertEqual(queue.providerSegment, [tracks[2]])
        XCTAssertEqual(queue.remaining, Array(tracks.suffix(2)))
    }

    func testModeChangeDoesNotReplayPlayedSongsOrMoveCurrentSong() {
        let tracks = (0..<8).map { track(String($0)) }
        var queue = PlaybackQueue(tracks: tracks, startingAt: 3)
        queue.reorder(mode: .weighted, weights: [:])
        XCTAssertEqual(queue.current, tracks[3])
        XCTAssertEqual(queue.entries.prefix(4).map(\.track), Array(tracks.prefix(4)))
        XCTAssertEqual(Set(queue.entries.dropFirst(4).map(\.id)), Set(4..<8))
        queue.reorder(mode: .order, weights: [:])
        XCTAssertEqual(queue.entries.map(\.track), tracks)
    }

    func testStatsOnlyProvidersNeverEnterAPlaybackQueue() {
        let queue = PlaybackQueue(tracks: [track("lastfm", .lastfm), track("spotify")])
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertEqual(queue.current?.providerID, .spotify)
    }

    func testEmptyQueueAndBoundsAreSafe() {
        var empty = PlaybackQueue()
        empty.next()
        empty.previous()
        empty.reorder(mode: .shuffle, weights: [:])
        XCTAssertNil(empty.current)
        XCTAssertTrue(empty.providerSegment.isEmpty)
        var single = PlaybackQueue(tracks: [track("only")], startingAt: 99)
        single.next()
        single.previous()
        XCTAssertEqual(single.index, 0)
    }

    private func track(_ id: String, _ provider: ProviderID = .spotify) -> UnifiedTrack {
        UnifiedTrack(key: trackKey(provider, id), providerID: provider, providerTrackID: id,
                     uri: "\(provider.rawValue):track:\(id)", name: id,
                     artists: [UnifiedArtist(id: "artist", name: "Artist")],
                     album: nil, albumArt: nil, durationMs: 180_000)
    }
}
