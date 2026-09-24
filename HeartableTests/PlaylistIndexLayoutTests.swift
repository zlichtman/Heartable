import XCTest
@testable import Heartable

/// The playlist index on disk: one file per playlist, tracks interned once in
/// memory, and the legacy single-file layout migrated on first read.
@MainActor
final class PlaylistIndexLayoutTests: XCTestCase {
    private var root: URL!
    private var owner: UUID!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaylistIndexLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        owner = UUID()
        await AccountSessionStore.prepare(for: owner)
    }

    override func tearDown() async throws {
        await AccountSessionStore.prepare(for: nil)
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    nonisolated private static func track(_ id: String) -> UnifiedTrack {
        .init(key: "spotify:\(id)", providerID: .spotify, providerTrackID: id,
              uri: "spotify:track:\(id)", name: "Song \(id)",
              artists: [.init(id: "a", name: "Artist")], album: nil, albumArt: nil, durationMs: 1)
    }

    nonisolated private static func playlist(_ id: String, count: Int) -> UnifiedPlaylist {
        .init(key: "spotify:\(id)", providerID: .spotify, playlistID: id, name: id,
              description: nil, image: nil, trackCount: count, owner: nil, contentRevision: "v1")
    }

    private var directory: URL {
        root.appendingPathComponent("playlist-tracks-\(owner.uuidString.lowercased())", isDirectory: true)
    }

    func testLegacySingleFileMigratesToDirectoryAndInternsSharedTracks() async throws {
        let shared = Self.track("shared")
        let legacy: [String: Any] = [
            "version": 1,
            "entries": [
                "spotify:a": entryJSON(id: "a", tracks: [shared, Self.track("a1")]),
                "spotify:b": entryJSON(id: "b", tracks: [shared, Self.track("b1"), shared]),
            ],
        ]
        let legacyURL = root.appendingPathComponent("playlist-tracks-\(owner.uuidString.lowercased()).json")
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyURL)

        let repo = PlaylistTracksRepository(fetch: { _ in .unavailable }, persistenceEnabled: true, cacheRoot: root)
        await repo.hydrate()
        XCTAssertEqual(repo.debugResidentTrackCount, 0)
        await repo.load(Self.playlist("a", count: 2))
        await repo.load(Self.playlist("b", count: 3))

        XCTAssertEqual(repo.tracks(for: Self.playlist("a", count: 2)).map(\.key), ["spotify:shared", "spotify:a1"])
        XCTAssertEqual(repo.tracks(for: Self.playlist("b", count: 3)).map(\.key), ["spotify:shared", "spotify:b1", "spotify:shared"])
        XCTAssertEqual(repo.debugUniqueTrackCount, 3, "A song in two playlists is held once")
        XCTAssertEqual(repo.debugOccurrenceCount, 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path), "The legacy file is replaced")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(PlaylistTracksRepository.fileName(for: "spotify:a")).path))
    }

    func testSyncWritesOnePlaylistFileEachAndRemovalDeletesIt() async throws {
        let a = Self.playlist("a", count: 2), b = Self.playlist("b", count: 1)
        let repo = PlaylistTracksRepository(fetch: { playlist in
            playlist.playlistID == "a" ? .success([Self.track("x"), Self.track("y")]) : .success([Self.track("x")])
        }, persistenceEnabled: true, cacheRoot: root)
        await repo.synchronize([a, b])
        let fileA = directory.appendingPathComponent(PlaylistTracksRepository.fileName(for: a.key))
        let fileB = directory.appendingPathComponent(PlaylistTracksRepository.fileName(for: b.key))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileB.path))
        XCTAssertEqual(repo.debugResidentTrackCount, 0)

        // A fresh instance reads the directory back, one playlist at a time.
        let again = PlaylistTracksRepository(fetch: { _ in .unavailable }, persistenceEnabled: true, cacheRoot: root)
        await again.hydrate()
        XCTAssertEqual(again.debugResidentTrackCount, 0)
        await again.load(a)
        await again.load(b)
        XCTAssertEqual(again.tracks(for: a).map(\.key), ["spotify:x", "spotify:y"])
        XCTAssertEqual(again.tracks(for: b).map(\.key), ["spotify:x"])
        XCTAssertTrue(again.hasResolvedAll([a, b]))

        await again.remove(keys: [b.key])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileB.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertEqual(again.debugUniqueTrackCount, 2, "x is still referenced by a")
        XCTAssertFalse(again.hasResolved(b))
    }

    func testTransientReadNeverTouchesTheIndex() async {
        let repo = PlaylistTracksRepository(fetch: { _ in .success([Self.track("f")]) }, persistenceEnabled: true, cacheRoot: root)
        await repo.hydrate()
        let friend = Self.playlist("friend", count: 1)
        let read = await repo.readTransient(friend)
        XCTAssertEqual(read.items?.map(\.key), ["spotify:f"])
        XCTAssertFalse(repo.hasResolved(friend))
        XCTAssertEqual(repo.debugUniqueTrackCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRemovePlaylistIndexCacheLeavesTheBrowseAndMasterCaches() throws {
        let fm = FileManager.default
        let support = try XCTUnwrap(fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
            .appendingPathComponent("Heartable", isDirectory: true)
        let id = owner.uuidString.lowercased()
        let index = support.appendingPathComponent("playlist-tracks-\(id)", isDirectory: true)
        let master = support.appendingPathComponent("master-library-\(id).json")
        try fm.createDirectory(at: index, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: index.appendingPathComponent("index.json"))
        try Data("{}".utf8).write(to: master)
        defer { try? fm.removeItem(at: master) }

        AccountSessionStore.removePlaylistIndexCache(ownerID: owner)

        XCTAssertFalse(fm.fileExists(atPath: index.path))
        XCTAssertTrue(fm.fileExists(atPath: master.path))
    }

    private func entryJSON(id: String, tracks: [UnifiedTrack]) -> [String: Any] {
        let encoded = try! JSONEncoder().encode(tracks)
        let rows = try! JSONSerialization.jsonObject(with: encoded)
        return ["providerID": "spotify", "playlistID": id, "contentRevision": "v1", "catalogTrackCount": tracks.count,
                "tracks": rows, "loadedAt": 700_000_000.0, "lastAccessedAt": 700_000_000.0]
    }
}
