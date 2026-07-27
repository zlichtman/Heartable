import XCTest
@testable import Heartable

@MainActor
final class FriendProfileMusicConnectionTests: XCTestCase {
    private let viewerID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let friendID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

    func testCompatibilityRequiresFiveDistinctTracksFromEachPerson() {
        let entries = (0..<4).map {
            leaderboardEntry(
                title: "Shared \($0)",
                contributors: [viewerID, friendID]
            )
        }

        XCTAssertEqual(
            FriendCompatibilityAvailability.evaluate(
                entries: entries,
                viewerID: viewerID,
                friendID: friendID
            ),
            .insufficient
        )
    }

    func testLegacyProfileUsesEveryDefaultModuleInDefaultOrder() {
        XCTAssertEqual(
            FriendProfileModuleLayout.visibleModules(from: nil),
            ProfileModulePreferenceDTO.defaults.map(\.module)
        )
    }

    func testProfileModuleLayoutPreservesSavedOrderAndRemovesHiddenModules() {
        let preferences = [
            ProfileModulePreferenceDTO(module: .musicLinks, isVisible: true),
            ProfileModulePreferenceDTO(module: .topTracks, isVisible: false),
            ProfileModulePreferenceDTO(module: .compatibility, isVisible: true),
        ]

        XCTAssertEqual(
            FriendProfileModuleLayout.visibleModules(from: preferences),
            [
                .musicLinks,
                .compatibility,
                .featuredPlaylists,
                .listeningStats,
                .sharedMixtapes,
            ]
        )
    }

    func testCompatibilityShowsHonestZeroAfterBothReachThreshold() {
        let viewerEntries = (0..<5).map {
            leaderboardEntry(
                title: "Viewer \($0)",
                contributors: [viewerID]
            )
        }
        let friendEntries = (0..<5).map {
            leaderboardEntry(
                title: "Friend \($0)",
                contributors: [friendID]
            )
        }

        let availability = FriendCompatibilityAvailability.evaluate(
            entries: viewerEntries + friendEntries,
            viewerID: viewerID,
            friendID: friendID
        )

        guard case .available(let summary) = availability else {
            return XCTFail("Expected a compatibility result at the sample threshold")
        }
        XCTAssertEqual(summary.score, 0)
        XCTAssertEqual(summary.sharedTrackCount, 0)
        XCTAssertEqual(summary.viewerTrackCount, 5)
        XCTAssertEqual(summary.friendTrackCount, 5)
    }

    func testCompatibilityUsesExistingRealOverlapSummary() {
        var entries = (0..<4).map {
            leaderboardEntry(
                title: "Viewer \($0)",
                contributors: [viewerID]
            )
        }
        entries += (0..<4).map {
            leaderboardEntry(
                title: "Friend \($0)",
                contributors: [friendID]
            )
        }
        entries.append(
            leaderboardEntry(
                title: "Our Song",
                contributors: [viewerID, friendID],
                plays: 8
            )
        )

        let availability = FriendCompatibilityAvailability.evaluate(
            entries: entries,
            viewerID: viewerID,
            friendID: friendID
        )

        guard case .available(let summary) = availability else {
            return XCTFail("Expected enough real history")
        }
        XCTAssertEqual(summary.score, 20)
        XCTAssertEqual(summary.sharedTracks.first?.trackName, "Our Song")
        XCTAssertEqual(summary.sharedTracks.first?.combinedPlays, 8)
    }

    func testMixtapeFlowTrimsTitleCreatesThenShares() async throws {
        let mixtapeID = UUID()
        var receivedTitle: String?
        var receivedShare: (UUID, UUID)?
        let creator = FriendMixtapeCreator(
            create: { title in
                receivedTitle = title
                return mixtapeID
            },
            share: { id, friendID in
                receivedShare = (id, friendID)
            }
        )

        let outcome = try await creator.createAndShare(
            title: "  Night drive  ",
            friendID: friendID
        )

        XCTAssertEqual(receivedTitle, "Night drive")
        XCTAssertEqual(receivedShare?.0, mixtapeID)
        XCTAssertEqual(receivedShare?.1, friendID)
        XCTAssertEqual(outcome, .shared(mixtapeID))
    }

    func testMixtapeFlowPreservesCreatedTapeWhenSharingFails() async throws {
        struct ShareFailure: Error {}
        let mixtapeID = UUID()
        let creator = FriendMixtapeCreator(
            create: { _ in mixtapeID },
            share: { _, _ in throw ShareFailure() }
        )

        let outcome = try await creator.createAndShare(
            title: "For a friend",
            friendID: friendID
        )

        XCTAssertEqual(outcome, .createdButNotShared(mixtapeID))
    }

    private func leaderboardEntry(
        title: String,
        contributors: [UUID],
        plays: Int = 1
    ) -> SongLeaderboardEntryDTO {
        SongLeaderboardEntryDTO(
            trackUri: "heartable:\(title)",
            trackName: title,
            artist: "Artist",
            plays: plays,
            contributors: contributors.map {
                SongLeaderboardContributorDTO(
                    userId: $0.uuidString,
                    displayName: nil,
                    avatarUrl: nil
                )
            }
        )
    }
}
