import Foundation
import Observation

/// Backs the Discover tab: top tracks fanned across connected providers, the
/// friends song leaderboard, and the friends now-playing strip. Reads degrade
/// to empty on failure — nothing here throws to the UI. Ported from the RN
/// HeartableScreen data layer.
@MainActor
@Observable
final class DiscoverStore {
    private(set) var songBoard: [SongLeaderboardEntryDTO] = []
    private(set) var friendsNow: [FriendNowPlayingDTO] = []
    private(set) var loadingBoard = false

    private var boardRequestID = UUID()

    /// Friends song leaderboard for a play-count window (in days).
    func loadBoard(windowDays: Int) async {
        let requestID = UUID()
        boardRequestID = requestID
        loadingBoard = true
        defer {
            if boardRequestID == requestID { loadingBoard = false }
        }
        let fetched = await BackendAPI.shared.getSongLeaderboard(windowDays: windowDays)
        guard !Task.isCancelled, boardRequestID == requestID else { return }
        songBoard = fetched
    }

    /// Friends now-playing snapshots for the top strip.
    func loadFriends() async {
        friendsNow = await BackendAPI.shared.getFriendsNowPlaying()
    }
}
