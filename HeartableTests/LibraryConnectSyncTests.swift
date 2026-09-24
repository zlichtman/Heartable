import XCTest
@testable import Heartable

/// End-to-end: an account with no library connects a service, and the shell's
/// synchronization must publish that service's playlists, liked songs and the
/// artist index without waiting on anything else.
@MainActor
final class LibraryConnectSyncTests: XCTestCase {
    private struct FakeProvider: MusicProvider {
        let id: ProviderID
        let playlistsResult: [UnifiedPlaylist]
        let likedResult: [UnifiedTrack]
        func isConnected() async -> Bool { true }
        func connect() async throws {}
        func disconnect() async {}
        func topTracks(range: StatRange, limit: Int) async -> [UnifiedTrack] { [] }
        func readTopTracks(range: StatRange, limit: Int) async -> ProviderRead<UnifiedTrack> { .success([]) }
        func likedTracks(limit: Int) async -> [UnifiedTrack] { likedResult }
        func playlists() async -> [UnifiedPlaylist] { playlistsResult }
        func playlistTracks(_ playlistID: String) async -> [UnifiedTrack] { likedResult }
        func search(_ query: String) async -> [UnifiedTrack] { [] }
        func play(_ track: UnifiedTrack) async throws {}
    }

    private func track(_ id: String, artist: String) -> UnifiedTrack {
        .init(key: "spotify:\(id)", providerID: .spotify, providerTrackID: id,
              uri: "spotify:track:\(id)", name: "Song \(id)",
              artists: [.init(id: "a-\(artist)", name: artist)],
              album: nil, albumArt: nil, durationMs: 200_000)
    }

    func testConnectingAServicePublishesItsLibraryAndArtistCounts() async throws {
        let owner = UUID()
        await AccountSessionStore.prepare(for: owner)
        defer { Task { await AccountSessionStore.prepare(for: nil) } }

        let liked = [track("1", artist: "Alpha"), track("2", artist: "Alpha"), track("3", artist: "Beta")]
        let playlist = UnifiedPlaylist(key: "spotify:p", providerID: .spotify, playlistID: "p", name: "Mix",
                                       description: nil, image: nil, trackCount: 3, owner: nil, contentRevision: "v1")
        let provider = FakeProvider(id: .spotify, playlistsResult: [playlist], likedResult: liked)
        let repository = PlaylistTracksRepository(fetch: { _ in .success(liked) }, persistenceEnabled: false)
        let session = LibrarySessionStore()

        // Launch with nothing paired, then "connect" Spotify: the provider set changes.
        await session.synchronize(providers: [], playlistTracks: repository)
        XCTAssertTrue(session.library.playlists.isEmpty)
        await session.synchronize(providers: [provider], playlistTracks: repository)

        XCTAssertEqual(session.library.playlists.map(\.key), ["spotify:p"])
        XCTAssertEqual(session.library.likedTracks.count, 3)
        XCTAssertFalse(session.library.loading)
        let alpha = session.library.artists.first { $0.name == "Alpha" }
        XCTAssertEqual(alpha?.count, 2, "Artist song counts come from the full index")
        XCTAssertEqual(session.library.artists.first { $0.name == "Beta" }?.count, 1)
        XCTAssertFalse(session.synchronizing)
        XCTAssertTrue(session.canStartAutomaticBackup(using: repository))
    }

    func testBackupWaitsForTheEntirePlaylistLoadAndDefersAfterFailure() async throws {
        await AccountSessionStore.prepare(for: UUID())
        let playlist = UnifiedPlaylist(key: "spotify:backup", providerID: .spotify, playlistID: "backup", name: "Large",
            description: nil, image: nil, trackCount: 1, owner: nil, contentRevision: "v1")
        let songs = [track("1", artist: "Artist")]
        let provider = FakeProvider(id: .spotify, playlistsResult: [playlist], likedResult: songs)
        let source = ControlledLoads()
        let repository = PlaylistTracksRepository(fetch: { _ in
            _ = await source.run("playlist")
            return .success(songs)
        }, persistenceEnabled: false)
        let session = LibrarySessionStore()
        await session.prepareCachedData(using: repository)
        XCTAssertFalse(session.canStartAutomaticBackup(using: repository), "Cached first paint is not load completion")
        let load = Task { await session.synchronize(providers: [provider], playlistTracks: repository) }
        for _ in 0..<1_000 {
            if await source.started.contains("playlist") { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(session.canStartAutomaticBackup(using: repository), "Playlist traversal still owns the load")
        await source.finish("playlist")
        await load.value
        XCTAssertTrue(session.canStartAutomaticBackup(using: repository))
        session.setActive(false)
        XCTAssertFalse(session.canStartAutomaticBackup(using: repository))
        session.setActive(true)
        session.reset()
        XCTAssertFalse(session.canStartAutomaticBackup(using: repository))

        let failing = PlaylistTracksRepository(fetch: { _ in .unavailable }, persistenceEnabled: false)
        await session.synchronize(providers: [provider], playlistTracks: failing, force: true)
        XCTAssertFalse(session.canStartAutomaticBackup(using: failing))
        XCTAssertTrue(session.needsSynchronization)
        await AccountSessionStore.prepare(for: nil)
    }
}
