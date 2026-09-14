import XCTest
@testable import Heartable

final class SpotifyLikedPagingTests: XCTestCase {
    private actor Pages {
        var offsets: [Int] = []
        var published: [String] = []
        func record(_ offset: Int) { offsets.append(offset) }
        func publish(_ batch: [String]) { published.append(contentsOf: batch) }
    }

    func testCursorCountsNullAndMalformedRowsAndPublishesBeforeNextRequest() async throws {
        let calls = Pages()
        let result = try await SpotifyAPI.readSavedTrackPages(
            token: "fixture", limit: 100, transform: { $0.id },
            onPage: { await calls.publish($0) }, gap: .zero
        ) { _, offset, _ in
            await calls.record(offset)
            let json: String
            switch offset {
            case 0:
                json = #"{"items":[null,{"track":{"id":"one","uri":"spotify:track:one"}},42],"next":"next"}"#
            case 3:
                let published = await calls.published
                XCTAssertEqual(published, ["one"], "The first page must publish before the second request")
                json = #"{"items":[null,null],"next":"next"}"#
            case 5:
                json = #"{"items":[{"track":{"id":"two","uri":"spotify:track:two"}}],"next":null}"#
            default:
                XCTFail("Repeated or incorrect page offset: \(offset)")
                throw ProviderError("Unexpected offset")
            }
            return try JSONDecoder().decode(Paged<SavedTrack>.self, from: Data(json.utf8))
        }
        XCTAssertEqual(result, ["one", "two"])
        let offsets = await calls.offsets
        XCTAssertEqual(offsets, [0, 3, 5])
    }

    func testLaterPageFailureKeepsPublishedPageButDoesNotClaimComplete() async {
        let calls = Pages()
        do {
            _ = try await SpotifyAPI.readSavedTrackPages(
                token: "fixture", limit: 100, transform: { $0.id },
                onPage: { await calls.publish($0) }, gap: .zero
            ) { _, offset, _ in
                guard offset == 0 else { throw ProviderError("Rate limited") }
                return try JSONDecoder().decode(Paged<SavedTrack>.self, from:
                    Data(#"{"items":[{"track":{"id":"one","uri":"spotify:track:one"}}],"next":"next"}"#.utf8))
            }
            XCTFail("Partial fetch must not become authoritative success")
        } catch {
            let published = await calls.published
            XCTAssertEqual(published, ["one"])
        }
    }

    func testTwentyThousandSongsArriveInBatchesOfAtMostFifty() async throws {
        let result = try await SpotifyAPI.readSavedTrackPages(
            token: "fixture", limit: Int.max, transform: SpotifyProvider.mapTrack,
            onPage: { XCTAssertLessThanOrEqual($0.count, 50) }, gap: .zero
        ) { _, offset, size in
            XCTAssertEqual(size, 50)
            let rows = (offset..<min(offset + size, 20_000)).map {
                ["track": ["id": "\($0)", "uri": "spotify:track:\($0)", "name": "Song \($0)"]]
            }
            let payload: [String: Any] = ["items": rows, "next": offset + size < 20_000 ? "next" as Any : NSNull()]
            return try JSONDecoder().decode(Paged<SavedTrack>.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        XCTAssertEqual(result.count, 20_000)
        XCTAssertEqual(Set(result.map(\.key)).count, 20_000)
        XCTAssertEqual(result.last?.providerTrackID, "19999")
    }

    func testUnavailableAndLocalTracksRemainMetadataButCannotEnterQueue() throws {
        let json = #"{"items":[{"id":"ok","uri":"spotify:track:ok"},{"id":null,"uri":"spotify:local:artist:album:song:100","is_local":true},{"id":"grey","uri":"spotify:track:grey","is_playable":false},{"id":"restricted","uri":"spotify:track:restricted","restrictions":{"reason":"market"}}],"next":null}"#
        let tracks = try JSONDecoder().decode(Paged<SpotifyTrack>.self, from: Data(json.utf8)).items!.map(SpotifyProvider.mapTrack)
        XCTAssertEqual(tracks.count, 4)
        XCTAssertEqual(Set(tracks.map(\.key)).count, 4)
        XCTAssertEqual(tracks.map { ProviderPlayback.isPlayable($0) }, [true, false, false, false])
        for mode in [ShuffleMode.order, .shuffle, .weighted] {
            XCTAssertEqual(PlaybackQueue(tracks: tracks, mode: mode).entries.map(\.track.key), ["spotify:ok"])
        }
        let roundTrip = try JSONDecoder().decode([UnifiedTrack].self, from: JSONEncoder().encode(tracks))
        XCTAssertEqual(roundTrip, tracks)
    }

    func testLegacyLocalURIIsNotPlayableAndMissingAvailabilityStillDecodes() throws {
        let track = SpotifyProvider.mapTrack(try JSONDecoder().decode(SpotifyTrack.self,
            from: Data(#"{"id":"legacy","uri":"spotify:local:a:b:c:1"}"#.utf8)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        json.removeValue(forKey: "playbackUnavailableReason")
        let legacy = try JSONDecoder().decode(UnifiedTrack.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.playbackUnavailableReason)
        XCTAssertFalse(ProviderPlayback.isPlayable(legacy))
    }
}

@MainActor
final class LikedPagePublicationTests: XCTestCase {
    private struct PagedProvider: MusicProvider {
        let id: ProviderID = .spotify
        let pages: [[UnifiedTrack]]
        let result: ProviderRead<UnifiedTrack>
        var afterPage: @Sendable () async -> Void = {}
        func isConnected() async -> Bool { true }
        func connect() async throws {}
        func disconnect() async {}
        func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] { [] }
        func likedTracks(limit: Int) async -> [UnifiedTrack] { result.items ?? [] }
        func playlists() async -> [UnifiedPlaylist] { [] }
        func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }
        func search(_ query: String) async -> [UnifiedTrack] { [] }
        func play(_ track: UnifiedTrack) async throws {}
        func readTopTracks(range: StatRange, limit: Int) async -> ProviderRead<UnifiedTrack> { .success([]) }
        func readPlaylists() async -> ProviderRead<UnifiedPlaylist> { .success([]) }
        func readLikedTracks(limit: Int, onPage: @escaping @Sendable ([UnifiedTrack]) async -> Void) async -> ProviderRead<UnifiedTrack> {
            for page in pages {
                await onPage(page)
                await afterPage()
            }
            return result
        }
    }

    private func track(_ id: String) -> UnifiedTrack {
        .init(key: "spotify:\(id)", providerID: .spotify, providerTrackID: id,
              uri: "spotify:track:\(id)", name: id, artists: [], album: nil, albumArt: nil, durationMs: 1000)
    }

    func testPartialPagePublishesImmediatelyAndFailureKeepsCachedSongs() async {
        await AccountSessionStore.prepare(for: UUID())
        let store = LibraryStore()
        let old = track("old"), new = track("new")
        await store.loadAll(providers: [PagedProvider(pages: [[old]], result: .success([old]))], force: true)
        let failing = PagedProvider(pages: [[new]], result: .unavailable, afterPage: {
            await MainActor.run {
                XCTAssertEqual(store.likedTracks.map(\.key), [old.key, new.key])
                XCTAssertTrue(store.loadingLiked)
            }
        })
        await store.loadAll(providers: [failing], force: true)
        XCTAssertEqual(store.likedTracks.map(\.key), [old.key, new.key])
        XCTAssertNotNil(store.providerNotice)
        XCTAssertFalse(store.loadingLiked)
        await store.loadAll(providers: [PagedProvider(pages: [], result: .success([]))], force: true)
        XCTAssertTrue(store.likedTracks.isEmpty, "Only a complete successful read can remove old songs")
        await AccountSessionStore.prepare(for: nil)
    }

    func testResetRejectsRemainingPagesAndFinalResult() async {
        await AccountSessionStore.prepare(for: UUID())
        let store = LibraryStore()
        let song = track("old-account")
        let provider = PagedProvider(pages: [[song], [song]], result: .success([song]), afterPage: {
            await store.reset()
        })
        await store.loadAll(providers: [provider], force: true)
        XCTAssertTrue(store.likedTracks.isEmpty)
        XCTAssertFalse(store.loadingLiked)
        await AccountSessionStore.prepare(for: nil)
    }
}
