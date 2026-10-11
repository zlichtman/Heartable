import Foundation

enum BackupInventoryLoader {
    static func load(snapshotID: UUID) async throws -> [BackupInventoryItem] {
        async let playlistsFetch = BackendAPI.shared.requireSnapshotPlaylists(snapshotID: snapshotID)
        async let likedFetch = BackendAPI.shared.requireSnapshotLikedTracks(snapshotID: snapshotID)

        let playlists = try await playlistsFetch
        let playlistRows = try await loadPlaylists(playlists, maxConcurrent: 6)
        var inventory = playlistRows
            .sorted { $0.index < $1.index }
            .flatMap(\.tracks)

        let liked = try await likedFetch
        inventory.append(contentsOf: liked.enumerated().map { offset, track in
            BackupInventoryItem(
                uri: track.spotifyTrackUri,
                name: track.trackName,
                artist: track.artistName,
                album: track.albumName,
                artworkURL: track.albumArtUrl,
                collection: "Liked Songs",
                position: track.position ?? offset,
                collectionID: "liked"
            )
        })
        return inventory
    }

    private static func loadPlaylists(
        _ playlists: [SnapshotPlaylistDTO],
        maxConcurrent: Int
    ) async throws -> [(index: Int, tracks: [BackupInventoryItem])] {
        try await withThrowingTaskGroup(of: (Int, [BackupInventoryItem]).self) { group in
            var results: [(index: Int, tracks: [BackupInventoryItem])] = []
            var nextIndex = 0

            func enqueue(_ index: Int) {
                let playlist = playlists[index]
                let collection = playlist.name?.isEmpty == false
                    ? playlist.name!
                    : "Untitled playlist"
                group.addTask {
                    let tracks = try await BackendAPI.shared.requireSnapshotTracks(
                        snapshotPlaylistID: playlist.id
                    )
                    return (index, tracks.enumerated().map { offset, track in
                        BackupInventoryItem(
                            uri: track.spotifyTrackUri,
                            name: track.trackName,
                            artist: track.artistName,
                            album: track.albumName,
                            artworkURL: track.albumArtUrl,
                            collection: collection,
                            position: track.position ?? offset,
                            collectionID: playlist.spotifyPlaylistId.flatMap { $0.isEmpty ? nil : $0 }
                        )
                    })
                }
            }

            while nextIndex < min(maxConcurrent, playlists.count) {
                enqueue(nextIndex)
                nextIndex += 1
            }
            for try await result in group {
                results.append((index: result.0, tracks: result.1))
                if nextIndex < playlists.count {
                    enqueue(nextIndex)
                    nextIndex += 1
                }
            }
            return results
        }
    }
}
