import Foundation

/// Metadata for one fully read backup. Check counts before displaying or caching
/// it: older clients can expose the parent before its children finish uploading.
struct BackupDetail: Sendable {
    let playlists: [SnapshotPlaylistDTO]
    let likedCount: Int

    func matches(_ snapshot: LibrarySnapshotDTO) -> Bool {
        guard Set(playlists.map(\.id)).count == playlists.count else { return false }
        if let expected = snapshot.playlistCount, playlists.count != expected { return false }
        if let expected = snapshot.likedCount, likedCount != expected { return false }
        if let expected = snapshot.trackCount {
            guard playlists.allSatisfy({ $0.trackCount != nil }),
                  playlists.reduce(0, { $0 + ($1.trackCount ?? 0) }) == expected else { return false }
        }
        return true
    }
}
