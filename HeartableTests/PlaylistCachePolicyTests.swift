import XCTest
@testable import Heartable

final class PlaylistCachePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testMatchingRevisionKeepsRecentPlaylistCache() {
        let playlist = makePlaylist(count: 12, revision: "snapshot-2")

        XCTAssertFalse(
            PlaylistTracksRepository.shouldRefresh(
                playlist: playlist,
                cachedRevision: "snapshot-2",
                cachedTrackCount: 12,
                loadedAt: now.addingTimeInterval(-60),
                now: now,
                force: false
            )
        )
    }

    func testRevisionChangeRefreshesEvenWhenSongCountMatches() {
        let playlist = makePlaylist(count: 12, revision: "snapshot-2")

        XCTAssertTrue(
            PlaylistTracksRepository.shouldRefresh(
                playlist: playlist,
                cachedRevision: "snapshot-1",
                cachedTrackCount: 12,
                loadedAt: now.addingTimeInterval(-60),
                now: now,
                force: false
            )
        )
    }

    func testTrackCountChangeRefreshesUnversionedProviderImmediately() {
        let playlist = makePlaylist(count: 13, revision: nil)

        XCTAssertTrue(
            PlaylistTracksRepository.shouldRefresh(
                playlist: playlist,
                cachedRevision: nil,
                cachedTrackCount: 12,
                loadedAt: now.addingTimeInterval(-60),
                now: now,
                force: false
            )
        )
    }

    func testUnversionedPlaylistGetsPeriodicSameCountRevalidation() {
        let playlist = makePlaylist(count: 12, revision: nil)
        let stale = now.addingTimeInterval(
            -PlaylistTracksRepository.unversionedRevalidationWindow - 1
        )

        XCTAssertTrue(
            PlaylistTracksRepository.shouldRefresh(
                playlist: playlist,
                cachedRevision: nil,
                cachedTrackCount: 12,
                loadedAt: stale,
                now: now,
                force: false
            )
        )
    }

    func testForceAlwaysRefreshes() {
        let playlist = makePlaylist(count: 12, revision: "snapshot-2")

        XCTAssertTrue(
            PlaylistTracksRepository.shouldRefresh(
                playlist: playlist,
                cachedRevision: "snapshot-2",
                cachedTrackCount: 12,
                loadedAt: now,
                now: now,
                force: true
            )
        )
    }

    func testPlaylistContentRevisionRoundTripsThroughCacheModel() throws {
        let playlist = makePlaylist(count: 12, revision: "snapshot-2")
        let data = try JSONEncoder().encode(playlist)
        let restored = try JSONDecoder().decode(UnifiedPlaylist.self, from: data)

        XCTAssertEqual(restored, playlist)
        XCTAssertEqual(restored.contentRevision, "snapshot-2")
    }

    private func makePlaylist(
        count: Int,
        revision: String?
    ) -> UnifiedPlaylist {
        UnifiedPlaylist(
            key: "spotify:road-trip",
            providerID: .spotify,
            playlistID: "road-trip",
            name: "Road Trip",
            description: nil,
            image: nil,
            trackCount: count,
            owner: "Zach",
            contentRevision: revision
        )
    }
}

final class FriendActivityCachePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFixedReactionVocabularyMatchesBackendConstraint() {
        XCTAssertEqual(
            FriendActivityReaction.allCases.map(\.rawValue),
            ["heart", "fire", "headphones", "on_repeat"]
        )
    }

    func testMissingOrStaleSnapshotRevalidatesButFreshSnapshotDoesNot() {
        XCTAssertTrue(
            FriendActivityRepository.shouldRefresh(
                lastUpdated: nil,
                now: now,
                force: false
            )
        )
        XCTAssertFalse(
            FriendActivityRepository.shouldRefresh(
                lastUpdated: now.addingTimeInterval(
                    -FriendActivityRepository.freshnessWindow + 1
                ),
                now: now,
                force: false
            )
        )
        XCTAssertTrue(
            FriendActivityRepository.shouldRefresh(
                lastUpdated: now.addingTimeInterval(
                    -FriendActivityRepository.freshnessWindow
                ),
                now: now,
                force: false
            )
        )
    }

    func testOptimisticReactionReplacementKeepsCountsConsistent() {
        let initial = entry(
            counts: ["heart": 3, "fire": 1],
            viewerReaction: .heart
        )

        let replaced = FriendActivityRepository.applyingReaction(
            .fire,
            to: initial
        )

        XCTAssertEqual(replaced.viewerReaction, .fire)
        XCTAssertEqual(replaced.reactionCount(.heart), 2)
        XCTAssertEqual(replaced.reactionCount(.fire), 2)
    }

    func testRemovingOnlyReactionDropsZeroCountKey() {
        let initial = entry(
            counts: ["headphones": 1],
            viewerReaction: .headphones
        )

        let removed = FriendActivityRepository.applyingReaction(nil, to: initial)

        XCTAssertNil(removed.viewerReaction)
        XCTAssertNil(removed.reactionCounts["headphones"])
        XCTAssertEqual(removed.reactionCount(.headphones), 0)
    }

    func testActivityDTOProvidesStableKeysetCursor() {
        let activity = entry(counts: [:], viewerReaction: nil)

        XCTAssertEqual(activity.cursor.playedAt, activity.playedAt)
        XCTAssertEqual(activity.cursor.activityID, activity.id)
    }

    func testRPCActivityPayloadDecodesReactionSummary() throws {
        let data = Data(
            """
            {
              "activity_id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
              "user_id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
              "display_name": "Friend",
              "handle": "friend",
              "avatar_url": null,
              "track_uri": "spotify:track:test",
              "track_name": "Pink Moon",
              "artist": "Nick Drake",
              "duration_ms": 132000,
              "album_art": null,
              "played_at": "2033-05-18T03:33:20Z",
              "reaction_counts": {"heart": 3, "fire": 1},
              "viewer_reaction": "heart"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(
            FriendActivityEntryDTO.self,
            from: data
        )

        XCTAssertEqual(decoded.viewerReaction, .heart)
        XCTAssertEqual(decoded.reactionCount(.heart), 3)
        XCTAssertEqual(decoded.durationMs, 132_000)
    }

    private func entry(
        counts: [String: Int],
        viewerReaction: FriendActivityReaction?
    ) -> FriendActivityEntryDTO {
        FriendActivityEntryDTO(
            activityId: UUID(
                uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
            )!,
            userId: UUID(
                uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
            )!,
            displayName: "Friend",
            trackUri: "spotify:track:test",
            trackName: "Pink Moon",
            artist: "Nick Drake",
            durationMs: 132_000,
            playedAt: "2033-05-18T03:33:20Z",
            reactionCounts: counts,
            viewerReaction: viewerReaction
        )
    }
}
