import XCTest
import Observation
@testable import Heartable

@MainActor
final class BoundedPlaylistLoadingTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await AccountSessionStore.prepare(for: UUID())
    }
    override func tearDown() async throws {
        await AccountSessionStore.prepare(for: nil)
        try? FileManager.default.removeItem(at: root)
    }
    nonisolated private static func playlist(_ id: String, count: Int = 3_000) -> UnifiedPlaylist {
        .init(key: "spotify:\(id)", providerID: .spotify, playlistID: id, name: id,
              description: nil, image: nil, trackCount: count, owner: nil, contentRevision: "v1")
    }
    nonisolated private static func tracks(_ id: String, count: Int = 3_000) -> [UnifiedTrack] {
        (0..<count).map { n in
            .init(key: "spotify:\(id)-\(n)", providerID: .spotify, providerTrackID: "\(id)-\(n)",
                  uri: "spotify:track:\(id)-\(n)", name: "Song \(n)",
                  artists: [.init(id: "artist", name: "Artist")], album: "Album",
                  albumArt: URL(string: "https://example.com/cover.jpg"), durationMs: 200_000)
        }
    }

    func testBrowsingManyLargePlaylistsKeepsBoundedCacheAndFullQueue() async {
        let repo = PlaylistTracksRepository(fetch: { .success(Self.tracks($0.playlistID)) }, cacheRoot: root)
        for n in 0..<10 {
            let playlist = Self.playlist("p\(n)")
            await repo.load(playlist)
            XCTAssertEqual(repo.tracks(for: playlist).count, 3_000, "Display window must never truncate playback")
            XCTAssertEqual(repo.tracks(for: playlist).last?.name, "Song 2999")
            XCTAssertLessThanOrEqual(repo.debugResidentTrackCount, 9_000)
        }
        XCTAssertTrue(repo.tracks(for: Self.playlist("p0")).isEmpty)
        XCTAssertTrue(repo.hasResolved(Self.playlist("p0")), "Eviction must not discard offline content")
        await repo.load(Self.playlist("p0"))
        XCTAssertEqual(repo.tracks(for: Self.playlist("p0")).count, 3_000)
    }

    func testWarmStartUsesDiskAndPreservesArtworkWithoutProviderRead() async {
        let playlist = Self.playlist("cached", count: 2)
        let writer = PlaylistTracksRepository(fetch: { _ in .success(Self.tracks("cached", count: 2)) }, cacheRoot: root)
        await writer.load(playlist)
        let reader = PlaylistTracksRepository(fetch: { _ in XCTFail("Fresh disk content should not refetch"); return .unavailable }, cacheRoot: root)
        await reader.hydrate()
        XCTAssertEqual(reader.debugResidentTrackCount, 0)
        XCTAssertTrue(reader.hasResolved(playlist))
        await reader.load(playlist)
        XCTAssertEqual(reader.tracks(for: playlist).count, 2)
        XCTAssertNotNil(reader.tracks(for: playlist).first?.albumArt)
    }

    func testRenderingPlaylistReadsNeverInvalidateObservation() async {
        let playlist = Self.playlist("render", count: 2)
        let repo = PlaylistTracksRepository(fetch: { _ in .success(Self.tracks("render", count: 2)) }, cacheRoot: root)
        await repo.load(playlist)
        withObservationTracking {
            for _ in 0..<100 {
                XCTAssertEqual(repo.tracks(for: playlist).count, 2)
                XCTAssertTrue(repo.hasLoaded(playlist))
                _ = repo.revision(for: playlist)
            }
        } onChange: {
            XCTFail("A render-time read must not mutate observable playlist state")
        }
        // A second render must remain a read even after observation is installed.
        XCTAssertEqual(repo.tracks(for: playlist).count, 2)
        XCTAssertEqual(repo.debugResidentTrackCount, 2)
    }

    func testFailedRefreshRetainsOfflineContent() async {
        let playlist = Self.playlist("cached", count: 2)
        let writer = PlaylistTracksRepository(fetch: { _ in .success(Self.tracks("cached", count: 2)) }, cacheRoot: root)
        await writer.load(playlist)
        let reader = PlaylistTracksRepository(fetch: { _ in .unavailable }, cacheRoot: root)
        await reader.load(playlist, force: true)
        XCTAssertTrue(reader.didFail(playlist))
        XCTAssertEqual(reader.tracks(for: playlist).count, 2)
        let index = await reader.index(for: [playlist])
        XCTAssertEqual(index.tracks.count, 2)
    }

    func testCancelledScreenStopsFetchAndNeverPublishesFailureOrPartialData() async {
        let source = ControlledLoads()
        let repo = PlaylistTracksRepository(fetch: { playlist in
            _ = await source.run(playlist.key)
            return .success(Self.tracks("cancel", count: 2))
        }, cacheRoot: root)
        let playlist = Self.playlist("cancel", count: 2)
        let load = Task { await repo.load(playlist) }
        for _ in 0..<1_000 {
            if await source.started.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let starts = await source.started
        XCTAssertEqual(starts.count, 1)
        load.cancel()
        await load.value
        for _ in 0..<1_000 {
            if await source.cancelled.contains(playlist.key) { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let cancellations = await source.cancelled
        XCTAssertTrue(cancellations.contains(playlist.key))
        XCTAssertFalse(repo.hasResolved(playlist))
        XCTAssertFalse(repo.didFail(playlist))
    }

    func testVisiblePlaylistCanLoadWhileIndexingAndCancellationKeepsIndexerAlive() async {
        let source = ControlledLoads()
        let repo = PlaylistTracksRepository(fetch: { playlist in
            _ = await source.run(playlist.key)
            return .success(Self.tracks(playlist.playlistID, count: 1))
        }, cacheRoot: root)
        let background = Self.playlist("background", count: 1)
        let foreground = Self.playlist("foreground", count: 1)
        let indexing = Task { await repo.synchronize([background]) }
        for _ in 0..<1_000 {
            if await source.started.count == 1 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let visible = Task { await repo.load(foreground) }
        for _ in 0..<1_000 {
            if await source.started.count == 2 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let started = await source.started
        XCTAssertEqual(Set(started), [background.key, foreground.key])
        visible.cancel()
        await visible.value
        await source.finish(background.key)
        await indexing.value
        XCTAssertTrue(repo.hasResolved(background))
        XCTAssertFalse(repo.hasResolved(foreground))
        let peak = await source.peak
        XCTAssertEqual(peak, 2)
    }

    func testBrokenLegacyCacheDoesNotBlockFreshLoadsOrGetDeleted() async throws {
        let owner = try XCTUnwrap(AccountSessionStore.currentOwnerID)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("playlist-tracks-\(owner.uuidString.lowercased()).json")
        try Data(#"{"version":1,"entries":{"broken":{"tracks":["#.utf8).write(to: legacy)
        let repo = PlaylistTracksRepository(fetch: { _ in .success(Self.tracks("new", count: 2)) }, cacheRoot: root)
        let playlist = Self.playlist("new", count: 2)
        await repo.load(playlist)
        XCTAssertEqual(repo.tracks(for: playlist).count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        let relaunched = PlaylistTracksRepository(fetch: { _ in XCTFail("Do not overwrite the new manifest with broken legacy data"); return .unavailable }, cacheRoot: root)
        await relaunched.load(playlist)
        XCTAssertEqual(relaunched.tracks(for: playlist).count, 2)
    }

    func testMasterProjectionDoesNotResurrectAuthoritativelyRemovedSongs() async {
        let master = MasterLibraryStore()
        await master.adopt(Self.tracks("before", count: 2), providerIDs: [.spotify])
        XCTAssertEqual(master.tracks.count, 2)
        await master.adopt([], providerIDs: [.spotify])
        XCTAssertTrue(master.tracks.isEmpty)
        XCTAssertTrue(master.artists.isEmpty)
    }

    func testCorruptPlaylistFileIsRepairedWithoutDiscardingOtherPlaylists() async throws {
        let owner = try XCTUnwrap(AccountSessionStore.currentOwnerID)
        let damaged = Self.playlist("damaged", count: 2)
        let good = Self.playlist("good", count: 2)
        let writer = PlaylistTracksRepository(fetch: { .success(Self.tracks($0.playlistID, count: 2)) }, cacheRoot: root)
        await writer.synchronize([damaged, good])
        let directory = root.appendingPathComponent("playlist-tracks-\(owner.uuidString.lowercased())")
        try Data("broken".utf8).write(to: directory.appendingPathComponent(PlaylistTracksRepository.fileName(for: damaged.key)))
        let reader = PlaylistTracksRepository(fetch: { playlist in
            XCTAssertEqual(playlist.key, damaged.key, "Good cached playlists must not be refetched")
            return .success(Self.tracks(playlist.playlistID, count: 2))
        }, cacheRoot: root)
        await reader.hydrate()
        let partial = await reader.index(for: [damaged, good])
        XCTAssertEqual(partial.tracks.count, 2)
        XCTAssertFalse(reader.hasResolved(damaged))
        XCTAssertTrue(reader.hasResolved(good))
        await reader.synchronize([damaged, good])
        let repaired = await reader.index(for: [damaged, good])
        XCTAssertEqual(repaired.tracks.count, 4)
    }
}

final class JSONDictionaryStreamTests: XCTestCase {
    func testReadsNestedEscapedUnicodeEntriesAcrossBufferBoundary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let input: [String: Any] = ["version": 1, "entries": [
            "a": ["name": String(repeating: "é\\\"}雪", count: 20_000), "tracks": [["id": "nested"]]],
            "b": ["name": "second", "tracks": []]
        ]]
        try JSONSerialization.data(withJSONObject: input).write(to: url)
        let read = try JSONDictionaryStream(url: url).mapEntries(named: "entries") { _, data in
            try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        XCTAssertEqual(read.entries.count, 2)
        XCTAssertEqual(read.entries["b"]?["name"] as? String, "second")
        XCTAssertEqual(read.entries["a"]?["name"] as? String, String(repeating: "é\\\"}雪", count: 20_000))
        XCTAssertEqual(try JSONDecoder().decode(Int.self, from: read.fields["version"]!), 1)
    }

    func testTruncatedMigrationIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"version":1,"entries":{"a":{"tracks":["#.utf8).write(to: url)
        XCTAssertThrowsError(try JSONDictionaryStream(url: url).mapEntries(named: "entries") { _, data in data })
    }
}
