import XCTest
@testable import Heartable

/// The library index holds each track once and answers artist lookups from
/// occurrence references; the numbers a user sees do not change.
@MainActor
final class LibraryIndexTests: XCTestCase {
    private struct FakeProvider: MusicProvider {
        let id: ProviderID
        let playlistsResult: [UnifiedPlaylist]
        let likedResult: [UnifiedTrack]
        func isConnected() async -> Bool { true }
        func connect() async throws {}
        func disconnect() async {}
        func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] { [] }
        func likedTracks(limit: Int) async -> [UnifiedTrack] { likedResult }
        func playlists() async -> [UnifiedPlaylist] { playlistsResult }
        func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { [] }
        func search(_ query: String) async -> [UnifiedTrack] { [] }
        func play(_ track: UnifiedTrack) async throws {}
    }

    nonisolated private static func track(_ id: String, artist: String) -> UnifiedTrack {
        .init(key: "spotify:\(id)", providerID: .spotify, providerTrackID: id,
              uri: "spotify:track:\(id)", name: "Song \(id)",
              artists: [.init(id: "a-\(artist)", name: artist)],
              album: nil, albumArt: nil, durationMs: 200_000)
    }

    nonisolated private static func playlist(_ id: String, count: Int) -> UnifiedPlaylist {
        .init(key: "spotify:\(id)", providerID: .spotify, playlistID: id, name: id,
              description: nil, image: nil, trackCount: count, owner: nil, contentRevision: "v1")
    }

    func testOccurrencesAreCountedWhileTracksAreStoredOnce() async throws {
        let owner = UUID()
        await AccountSessionStore.prepare(for: owner)
        defer { Task { await AccountSessionStore.prepare(for: nil) } }

        let hit = Self.track("hit", artist: "Alpha")
        let liked = [hit, Self.track("2", artist: "Alpha"), Self.track("3", artist: "Beta")]
        let lists = [Self.playlist("p1", count: 2), Self.playlist("p2", count: 1)]
        let provider = FakeProvider(id: .spotify, playlistsResult: lists, likedResult: liked)
        let repository = PlaylistTracksRepository(fetch: { playlist in
            playlist.playlistID == "p1" ? .success([hit, Self.track("3", artist: "Beta")]) : .success([hit])
        }, persistenceEnabled: false)
        let session = LibrarySessionStore()
        let before = session.library.indexRevision

        await session.synchronize(providers: [provider], playlistTracks: repository)

        let library = session.library
        XCTAssertGreaterThan(library.indexRevision, before)
        XCTAssertEqual(Set(library.indexedTracks.map(\.key)), ["spotify:hit", "spotify:2", "spotify:3"],
                       "The master library receives each track once")
        XCTAssertEqual(repository.debugResidentTrackCount, 0, "Indexing must not populate screen caches")
        XCTAssertEqual(repository.debugOccurrenceCount, 3)

        let alphaEntries = library.entries(forArtist: "alpha")
        XCTAssertEqual(alphaEntries.count, 4, "liked hit, liked 2, hit in p1, hit in p2")
        XCTAssertEqual(alphaEntries.compactMap { $0.playlist?.playlistID }.sorted(), ["p1", "p2"])
        XCTAssertEqual(library.artists.first { $0.name == "Alpha" }?.count, 2, "Counts stay per distinct song")
        XCTAssertEqual(library.artists.first { $0.name == "Beta" }?.count, 1)
    }

    func testAHundredPlaylistsSharingASongStayWithinOneCopyPerTrack() async {
        let owner = UUID()
        await AccountSessionStore.prepare(for: owner)
        defer { Task { await AccountSessionStore.prepare(for: nil) } }

        let sharedTracks = (0..<200).map { Self.track("s\($0)", artist: "Shared") }
        let lists = (0..<100).map { Self.playlist("p\($0)", count: 250) }
        let repository = PlaylistTracksRepository(fetch: { playlist in
            let own = (0..<50).map { Self.track("\(playlist.playlistID)-\($0)", artist: playlist.playlistID) }
            return .success(sharedTracks + own)
        }, persistenceEnabled: false)
        let footprintBefore = MemoryFootprint.current()

        await repository.synchronize(lists)

        XCTAssertEqual(repository.debugOccurrenceCount, 25_000)
        let index = await repository.index(for: lists)
        XCTAssertEqual(index.tracks.count, 5_200)
        XCTAssertEqual(repository.debugResidentTrackCount, 0)
        let grown = MemoryFootprint.current() > footprintBefore ? MemoryFootprint.current() - footprintBefore : 0
        XCTAssertLessThan(MemoryFootprint.megabytes(grown), 200, "25k occurrences must not cost 25k tracks")
    }
}
