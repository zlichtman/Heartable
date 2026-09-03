import XCTest
@testable import Heartable

final class AccountIsolationTests: XCTestCase {
    @MainActor
    func testMeStoreHydratesOnlyTheActivatedAccountsCachedProfile() throws {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let cached = ProfileDTO(
            userId: first,
            displayName: "Cached Listener",
            avatarUrl: "https://example.com/avatar.jpg",
            handle: "cached_listener"
        )
        let data = try JSONEncoder().encode(cached)
        AccountSessionStore.setDefault(
            data,
            forKey: AccountSessionStore.profileCacheKey,
            ownerID: first
        )
        defer {
            AccountSessionStore.removeDefault(
                forKey: AccountSessionStore.profileCacheKey,
                ownerID: first
            )
        }

        let store = MeStore()
        store.activate(userID: first)
        XCTAssertEqual(store.displayName, "Cached Listener")
        XCTAssertEqual(store.handle, "cached_listener")
        XCTAssertEqual(store.avatarUrlString, "https://example.com/avatar.jpg")

        store.activate(userID: second)
        XCTAssertEqual(store.displayName, "Heartable user")
        XCTAssertNil(store.handle)
        XCTAssertNil(store.avatarUrlString)
    }

    @MainActor
    func testMeStoreProfileMutationPersistsForTheNextLaunch() {
        let userID = UUID()
        defer {
            AccountSessionStore.removeDefault(
                forKey: AccountSessionStore.profileCacheKey,
                ownerID: userID
            )
        }

        let firstStore = MeStore()
        firstStore.setNameHandle(
            displayName: "Immediate Name",
            handle: "instant",
            userID: userID
        )

        let relaunchedStore = MeStore()
        relaunchedStore.activate(userID: userID)
        XCTAssertEqual(relaunchedStore.displayName, "Immediate Name")
        XCTAssertEqual(relaunchedStore.handle, "instant")
    }

    func testLibraryCacheFilenameIsScopedToAccount() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        let firstName = AccountSessionStore.scopedFilename(
            "master-library",
            ext: "json",
            ownerID: first
        )
        let secondName = AccountSessionStore.scopedFilename(
            "master-library",
            ext: "json",
            ownerID: second
        )

        XCTAssertNotEqual(firstName, secondName)
        XCTAssertTrue(firstName.contains(first.uuidString.lowercased()))
        XCTAssertEqual(
            AccountSessionStore.scopedFilename(
                "master-library",
                ext: "json",
                ownerID: nil
            ),
            "master-library-unowned.json"
        )
    }

    func testProviderKeysAreScopedToHeartableAccount() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        let firstKey = AccountSessionStore.scopedKey(
            "heartable_spotify_refresh",
            ownerID: first
        )
        let secondKey = AccountSessionStore.scopedKey(
            "heartable_spotify_refresh",
            ownerID: second
        )

        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertTrue(firstKey.contains(first.uuidString.lowercased()))
        XCTAssertTrue(firstKey.hasSuffix(".heartable_spotify_refresh"))
    }

    func testProviderManifestPrefersNewestAccountDecision() {
        let userID = UUID()
        let remoteConnected = ProviderConnectionDTO(
            userId: userID,
            providerId: ProviderID.spotify.rawValue,
            connected: true,
            metadata: [:],
            connectedAt: "2026-09-01T12:00:00Z",
            updatedAt: "2026-09-01T12:00:00Z"
        )
        let localDisconnected = ProviderConnectionDTO(
            userId: userID,
            providerId: ProviderID.spotify.rawValue,
            connected: false,
            metadata: [:],
            connectedAt: nil,
            updatedAt: "2026-09-02T12:00:00Z"
        )

        let merged = ProvidersStore.merge(
            local: [localDisconnected],
            remote: [remoteConnected]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].connected)
    }

    func testProviderManifestLetsNewerServerPairingRestoreAfterReinstall() {
        let userID = UUID()
        let staleLocal = ProviderConnectionDTO(
            userId: userID,
            providerId: ProviderID.apple.rawValue,
            connected: false,
            metadata: [:],
            connectedAt: nil,
            updatedAt: "2026-09-01T12:00:00Z"
        )
        let serverPairing = ProviderConnectionDTO(
            userId: userID,
            providerId: ProviderID.apple.rawValue,
            connected: true,
            metadata: [:],
            connectedAt: "2026-09-02T12:00:00Z",
            updatedAt: "2026-09-02T12:00:00Z"
        )

        let merged = ProvidersStore.merge(local: [staleLocal], remote: [serverPairing])

        XCTAssertTrue(merged[0].connected)
    }

    func testProviderManifestComparesEquivalentTimestampFormatsChronologically() {
        let userID = UUID()
        let actuallyNewer = ProviderConnectionDTO(
            userId: userID,
            providerId: ProviderID.spotify.rawValue,
            connected: false,
            metadata: [:],
            connectedAt: nil,
            updatedAt: "2026-09-03T12:00:00.900Z"
        )
        let lexicallyMisleading = ProviderConnectionDTO(
            userId: userID,
            providerId: ProviderID.spotify.rawValue,
            connected: true,
            metadata: [:],
            connectedAt: nil,
            updatedAt: "2026-09-03T12:00:00+00:00"
        )

        let merged = ProvidersStore.merge(
            local: [actuallyNewer],
            remote: [lexicallyMisleading]
        )

        XCTAssertFalse(merged[0].connected)
    }

    @MainActor
    func testOnboardingCompletionIsCachedWithTheAccountProfile() {
        let userID = UUID()
        defer {
            AccountSessionStore.removeDefault(
                forKey: AccountSessionStore.profileCacheKey,
                ownerID: userID
            )
        }

        let firstStore = MeStore()
        firstStore.markOnboardingCompleted(userID: userID)
        XCTAssertTrue(firstStore.hasCompletedOnboarding)

        let relaunchedStore = MeStore()
        relaunchedStore.activate(userID: userID)
        XCTAssertTrue(relaunchedStore.hasCompletedOnboarding)
        XCTAssertTrue(relaunchedStore.hasResolvedAccount)
    }

    func testEmailNormalizationIsStableAcrossAccountActions() {
        XCTAssertEqual(
            AuthStore.normalizedEmail("  Zach.Lichtman@Example.COM\n"),
            "zach.lichtman@example.com"
        )
    }

    func testFriendInviteParserAcceptsOnlyNonemptyInviteLinks() {
        XCTAssertEqual(
            FriendLinks.inviteCode(
                from: URL(string: "heartable://add-friend?code=AbC%20123")!
            ),
            "AbC 123"
        )
        XCTAssertNil(
            FriendLinks.inviteCode(
                from: URL(string: "heartable://add-friend?code=%20%20")!
            )
        )
        XCTAssertNil(
            FriendLinks.inviteCode(
                from: URL(string: "heartable://callback?code=secret")!
            )
        )
        XCTAssertNil(
            FriendLinks.inviteCode(
                from: URL(string: "https://example.com/add-friend?code=secret")!
            )
        )
    }

    func testAcceptedFriendshipWinsOverLegacyPendingDuplicate() {
        let me = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let friend = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let acceptedID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let pendingID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let rows = [
            FriendshipDTO(
                id: pendingID,
                requesterId: me,
                addresseeId: friend,
                status: "pending",
                createdAt: nil
            ),
            FriendshipDTO(
                id: acceptedID,
                requesterId: friend,
                addresseeId: me,
                status: "accepted",
                createdAt: nil
            )
        ]

        XCTAssertEqual(
            FriendRelationship.resolve(rows: rows, viewerID: me, otherID: friend),
            .friends(acceptedID)
        )
    }

    func testReversePendingRequestResolvesAsIncoming() {
        let me = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let friend = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let requestID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let row = FriendshipDTO(
            id: requestID,
            requesterId: friend,
            addresseeId: me,
            status: "pending",
            createdAt: nil
        )

        XCTAssertEqual(
            FriendRelationship.resolve(rows: [row], viewerID: me, otherID: friend),
            .incoming(requestID)
        )
    }

    func testNowPlayingRequiresActiveFreshTrack() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fresh = ISO8601DateFormatter().string(from: now.addingTimeInterval(-30))
        let stale = ISO8601DateFormatter().string(from: now.addingTimeInterval(-120))

        XCTAssertTrue(
            FriendActivityPolicy.isLive(
                isPlaying: true,
                trackName: "Pink Moon",
                updatedAt: fresh,
                now: now
            )
        )
        XCTAssertFalse(
            FriendActivityPolicy.isLive(
                isPlaying: true,
                trackName: "Pink Moon",
                updatedAt: stale,
                now: now
            )
        )
        XCTAssertFalse(
            FriendActivityPolicy.isLive(
                isPlaying: false,
                trackName: "Pink Moon",
                updatedAt: fresh,
                now: now
            )
        )
    }

    func testFriendLinksResetClearsPendingInvite() async {
        await MainActor.run {
            let links = FriendLinks()
            links.handle(URL(string: "heartable://add-friend?code=friend-code")!)
            XCTAssertEqual(links.pendingCode, "friend-code")

            links.resetForAccountTransition()

            XCTAssertNil(links.pendingCode)
            XCTAssertNil(links.routeRequestID)
        }
    }

    func testLegacySongMessagePayloadStillDecodes() throws {
        let data = Data(
            """
            {
              "song": {
                "uri": "spotify:track:abc123",
                "name": "Pink Moon",
                "artist": "Nick Drake",
                "art": "https://example.com/pink-moon.jpg"
              }
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(MessagePayload.self, from: data)

        XCTAssertEqual(payload.song?.uri, "spotify:track:abc123")
        XCTAssertNil(payload.song?.providerID)
        XCTAssertNil(payload.song?.providerTrackID)
        XCTAssertNil(payload.song?.durationMs)
    }

    func testSongMessagePlaybackIdentityUsesBackendFieldNames() throws {
        let payload = MessagePayload(song: .init(
            uri: "spotify:track:abc123",
            name: "Pink Moon",
            artist: "Nick Drake",
            art: nil,
            providerID: ProviderID.spotify.rawValue,
            providerTrackID: "abc123",
            durationMs: 243_000
        ))

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
                as? [String: Any]
        )
        let song = try XCTUnwrap(object["song"] as? [String: Any])

        XCTAssertEqual(song["provider_id"] as? String, "spotify")
        XCTAssertEqual(song["provider_track_id"] as? String, "abc123")
        XCTAssertEqual(song["duration_ms"] as? Int, 243_000)
    }
}
