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
    }
}
