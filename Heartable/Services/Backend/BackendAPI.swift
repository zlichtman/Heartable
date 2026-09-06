import Foundation
import Observation
import Supabase

/// Typed wrappers over the reused Supabase schema (tables / RPCs / edge fns).
/// One method per backend operation; feature phases add their own. Reads return
/// optionals/empties rather than throwing on "no row".
struct BackendAPI: Sendable {
    static let shared = BackendAPI()

    private var client: SupabaseClient { SupabaseClientProvider.shared }

    /// Current signed-in user id, or nil. Used to scope mutations + cascades.
    private func myUID() async -> UUID? {
        try? await client.auth.session.user.id
    }

    /// Resolve the live Supabase identity and optionally require it to still be
    /// the account that initiated a long-running operation. This closes the
    /// small but important window where an old task resumes after account switch
    /// and would otherwise stamp its payload onto the new session.
    private func myUID(expected expectedUserID: UUID?) async -> UUID? {
        guard let uid = await myUID() else { return nil }
        guard expectedUserID == nil || expectedUserID == uid else { return nil }
        return uid
    }

    private var nowISO: String { ISO8601DateFormatter().string(from: Date()) }

    // MARK: - Profiles

    func getMyProfile(userID: UUID) async throws -> ProfileDTO? {
        let rows: [ProfileDTO] = try await client
            .from("profiles")
            .select()
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func upsertMyProfile(_ profile: ProfileDTO) async throws {
        try await client.from("profiles").upsert(profile).execute()
    }

    // MARK: - Profiles / discoverability

    /// Find a profile by handle or share/invite code via the `find_profile` RPC.
    /// NOTE: the RPC returns at most one row (handle/share_code lookup), so the
    /// RN de-duplication-by-userId logic collapses to a passthrough here.
    func findProfiles(query: String) async throws -> [FoundProfileDTO] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let rows: [FoundProfileDTO] = try await client
            .rpc("find_profile", params: ["p_query": AnyJSON.string(q)])
            .execute()
            .value
        return rows
    }

    /// Partial profile update (display name / handle / avatar). Upsert so it
    /// works even with no existing row. Handle is lowercased to match RN.
    func updateMyProfile(displayName: String?? = nil,
                         handle: String?? = nil,
                         avatarUrl: String?? = nil) async throws {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        var row = ProfileUpsertDTO(userId: uid, updatedAt: nowISO)
        if case let .some(value) = displayName { row.displayName = value }
        if case let .some(value) = handle { row.handle = value?.lowercased() }
        if case let .some(value) = avatarUrl { row.avatarUrl = value }
        try await client.from("profiles").upsert(row, onConflict: "user_id").execute()
    }

    /// Persist onboarding on the Heartable account, not just this installation.
    /// This prevents a reinstall or second device from presenting setup again.
    func completeOnboarding(userID expectedUserID: UUID? = nil) async throws {
        guard let uid = await myUID(expected: expectedUserID) else {
            throw BackendError.notSignedIn
        }
        let row = ProfileUpsertDTO(
            userId: uid,
            onboardingCompletedAt: nowISO,
            updatedAt: nowISO
        )
        try await client.from("profiles")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    // MARK: - Account provider connections

    /// The durable, non-secret pairing manifest for the signed-in account.
    func providerConnections() async throws -> [ProviderConnectionDTO] {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        return try await client.from("provider_connections")
            .select()
            .eq("user_id", value: uid.uuidString)
            .execute()
            .value
    }

    /// Record account-level connection intent. Provider credentials remain in
    /// Keychain; only safe restoration metadata is accepted by callers here.
    func upsertProviderConnection(
        providerId: ProviderID,
        connected: Bool,
        metadata: [String: String],
        userID expectedUserID: UUID? = nil
    ) async throws {
        guard let uid = await myUID(expected: expectedUserID) else {
            throw BackendError.notSignedIn
        }
        let timestamp = nowISO
        let row = ProviderConnectionDTO(
            userId: uid,
            providerId: providerId.rawValue,
            connected: connected,
            metadata: metadata,
            connectedAt: connected ? timestamp : nil,
            updatedAt: timestamp
        )
        try await client.from("provider_connections")
            .upsert(row, onConflict: "user_id,provider_id")
            .execute()
    }

    /// Ensure the signed-in user has a profile row (spotify quick-signup fallback).
    func upsertMyProfileSpotify(spotifyId: String,
                                displayName: String?,
                                avatarUrl: String?) async throws {
        guard let uid = await myUID() else { return }
        let row = ProfileUpsertDTO(
            userId: uid,
            spotifyId: spotifyId,
            displayName: displayName,
            avatarUrl: avatarUrl,
            handle: spotifyId.lowercased(),
            updatedAt: nowISO
        )
        try await client.from("profiles").upsert(row, onConflict: "user_id").execute()
    }

    /// Read the public playlist selection that a user chose for their profile.
    /// The avatars bucket is already public profile media; using a versioned JSON
    /// object gives this feature a deployable persistence contract without
    /// requiring clients to race a database migration.
    func getProfileCuration(userID: UUID) async -> ProfileCurationDTO? {
        try? await fetchProfileCuration(userID: userID)
    }

    /// Throwing variant used by the signed-in user's editor. Public friend
    /// profiles remain best-effort through `getProfileCuration`, while an owner
    /// editing their own profile needs to distinguish "no selection yet" from a
    /// network or decoding failure.
    func fetchProfileCuration(userID: UUID) async throws -> ProfileCurationDTO? {
        let path = Self.profileCurationPath(userID)
        guard let publicURL = try? client.storage.from("avatars").getPublicURL(path: path),
              var components = URLComponents(url: publicURL, resolvingAgainstBaseURL: false) else {
            throw BackendError.message("Couldn’t create the profile playlist URL.")
        }
        // Supabase's public object URL may sit behind a CDN. The timestamp makes
        // a just-saved profile selection visible on the next view without
        // disabling caching for stable public profiles.
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970 / 30)))
        ]
        guard let url = components.url else {
            throw BackendError.message("Couldn’t create the profile playlist URL.")
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.message("The profile playlist response was invalid.")
        }
        if Self.isMissingStorageObject(statusCode: http.statusCode, data: data) {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.message("Couldn’t load featured playlists. Try again.")
        }
        let result = try JSONDecoder().decode(ProfileCurationDTO.self, from: data)
        guard (ProfileCurationDTO.oldestSupportedVersion...ProfileCurationDTO.currentVersion)
            .contains(result.version) else {
            throw BackendError.message("Profile settings were saved by a newer app version.")
        }
        return result
    }

    /// Supabase Storage can encode a missing public object as either HTTP 404 or
    /// HTTP 400 with a JSON `statusCode`/message carrying 404. Both mean the user
    /// has not saved profile curation yet, which is a valid empty state.
    nonisolated static func isMissingStorageObject(
        statusCode: Int,
        data: Data
    ) -> Bool {
        if statusCode == 404 { return true }
        guard statusCode == 400,
              let payload = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return false
        }
        let embeddedStatus = (payload["statusCode"] as? String)
            ?? (payload["status"] as? String)
        let message = [
            payload["error"] as? String,
            payload["message"] as? String,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        return embeddedStatus == "404"
            || message.contains("not found")
            || message.contains("not_found")
    }

    /// Replace the signed-in user's ordered public playlist selection and public
    /// module visibility/order as one object. One atomic upload prevents a save
    /// from reverting another part of the profile.
    func updateProfileCuration(
        playlists: [UnifiedPlaylist],
        modules: [ProfileModulePreferenceDTO]
    ) async throws {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        let document = ProfileCurationDTO(
            playlists: playlists.prefix(6).map(ProfilePlaylistDTO.init),
            modules: modules,
            updatedAt: Date()
        )
        let data = try JSONEncoder().encode(document)
        _ = try await client.storage
            .from("avatars")
            .upload(
                Self.profileCurationPath(uid),
                data: data,
                options: FileOptions(
                    contentType: "application/json",
                    upsert: true
                )
            )
    }

    private static func profileCurationPath(_ userID: UUID) -> String {
        "\(userID.uuidString.lowercased())/profile-curation.json"
    }

    /// Record/update the current user's handle for one connected service.
    func upsertProfileLink(providerId: ProviderID,
                           handle: String,
                           displayName: String? = nil) async throws {
        guard let uid = await myUID() else { return }
        let row = ProfileLinkDTO(
            userId: uid,
            providerId: providerId.rawValue,
            handle: handle,
            displayName: displayName,
            updatedAt: nowISO
        )
        try await client.from("profile_links")
            .upsert(row, onConflict: "user_id,provider_id")
            .execute()
    }

    /// Remove a service link (disconnecting that provider).
    func removeProfileLink(providerId: ProviderID) async {
        guard let uid = await myUID() else { return }
        _ = try? await client.from("profile_links")
            .delete()
            .eq("user_id", value: uid.uuidString)
            .eq("provider_id", value: providerId.rawValue)
            .execute()
    }

    // MARK: - Friends

    /// Resolve the relationship in both directions. This is intentionally
    /// throwing: an unavailable relationship must never be treated as `.none`.
    func relationship(with otherID: UUID) async throws -> FriendRelationship {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        if uid == otherID { return .blocked }
        let rows = try await friendshipRows(viewerID: uid, otherID: otherID)
        return FriendRelationship.resolve(rows: rows, viewerID: uid, otherID: otherID)
    }

    private func friendshipRows(viewerID: UUID, otherID: UUID) async throws -> [FriendshipDTO] {
        let uidString = viewerID.uuidString
        let otherString = otherID.uuidString
        return try await client
            .from("friendships")
            .select()
            .or(
                "and(requester_id.eq.\(uidString),addressee_id.eq.\(otherString)),"
                    + "and(requester_id.eq.\(otherString),addressee_id.eq.\(uidString))"
            )
            .execute()
            .value
    }

    /// Insert a new request only when no relationship exists. Unlike the previous
    /// upsert, this can never rewrite an accepted friendship back to pending.
    func sendFriendRequest(addresseeID: UUID) async throws -> FriendRequestOutcome {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        if uid == addresseeID { throw BackendError.message("That's you!") }

        let existingRows = try await friendshipRows(viewerID: uid, otherID: addresseeID)
        switch FriendRelationship.resolve(
            rows: existingRows,
            viewerID: uid,
            otherID: addresseeID
        ) {
        case .friends(let id): return .alreadyFriends(id)
        case .outgoing(let id): return .outgoingPending(id)
        case .incoming(let id): return .incomingPending(id)
        case .blocked: return .blocked
        case .none: break
        }

        // A directional unique constraint may retain declined requests. Reopen
        // only the viewer's own declined row with a status-scoped update; accepted
        // rows were handled above and can never pass this predicate.
        if let declined = existingRows.first(where: {
            $0.requesterId == uid
                && $0.addresseeId == addresseeID
                && $0.status == "declined"
        }) {
            try await client.from("friendships")
                .update(FriendStatusUpdateDTO(status: "pending", updatedAt: nowISO))
                .eq("id", value: declined.id.uuidString)
                .eq("requester_id", value: uid.uuidString)
                .eq("status", value: "declined")
                .execute()
            return .sent
        }

        let row = FriendRequestInsertDTO(
            requesterId: uid,
            addresseeId: addresseeID,
            status: "pending"
        )
        do {
            try await client.from("friendships").insert(row).execute()
            return .sent
        } catch {
            // A concurrent request may have won between the read and insert.
            // Re-resolve so callers receive the authoritative state.
            switch try await relationship(with: addresseeID) {
            case .friends(let id): return .alreadyFriends(id)
            case .outgoing(let id): return .outgoingPending(id)
            case .incoming(let id): return .incomingPending(id)
            case .blocked: return .blocked
            case .none: throw error
            }
        }
    }

    func respondToFriendRequest(id: UUID, accept: Bool) async throws {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        guard let existing = try await friendship(id: id),
              existing.addresseeId == uid,
              existing.status == "pending" else {
            throw BackendError.message("This friend request is no longer available.")
        }
        let row = FriendStatusUpdateDTO(status: accept ? "accepted" : "declined", updatedAt: nowISO)
        try await client.from("friendships")
            .update(row)
            .eq("id", value: id.uuidString)
            .eq("addressee_id", value: uid.uuidString)
            .eq("status", value: "pending")
            .execute()
    }

    func cancelFriendRequest(id: UUID) async throws {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        guard let existing = try await friendship(id: id),
              existing.requesterId == uid,
              existing.status == "pending" else {
            throw BackendError.message("This friend request is no longer pending.")
        }
        try await client.from("friendships")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("requester_id", value: uid.uuidString)
            .eq("status", value: "pending")
            .execute()
    }

    func removeFriend(id: UUID) async throws {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        guard let existing = try await friendship(id: id),
              (existing.requesterId == uid || existing.addresseeId == uid),
              existing.status == "accepted" else {
            throw BackendError.message("This friendship is no longer available.")
        }
        try await client.from("friendships")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("status", value: "accepted")
            .execute()
    }

    private func friendship(id: UUID) async throws -> FriendshipDTO? {
        let rows: [FriendshipDTO] = try await client
            .from("friendships")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Fetch profiles for a set of user ids, keyed by id.
    private func profilesByIDs(_ ids: [UUID]) async -> [UUID: ProfileDTO] {
        (try? await fetchProfilesByIDs(ids)) ?? [:]
    }

    private func fetchProfilesByIDs(_ ids: [UUID]) async throws -> [UUID: ProfileDTO] {
        guard !ids.isEmpty else { return [:] }
        let rows: [ProfileDTO] = try await client
            .from("profiles")
            .select()
            .in("user_id", values: ids.map(\.uuidString))
            .execute()
            .value
        return Dictionary(rows.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Accepted friends, hydrated with the *other* party's profile.
    func listFriends() async -> [FriendDTO] {
        (try? await fetchFriends()) ?? []
    }

    /// Throwing accepted-friends read for surfaces where a transient backend
    /// failure must preserve the last good list instead of looking like zero friends.
    func fetchFriends() async throws -> [FriendDTO] {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        let rows: [FriendshipDTO] = try await client
            .from("friendships")
            .select()
            .eq("status", value: "accepted")
            .execute()
            .value
        // RLS is still the security boundary, but filter and de-duplicate here so
        // legacy reverse-direction rows cannot duplicate UI identity or crash a
        // dictionary built by user id.
        var rowByOtherID: [UUID: FriendshipDTO] = [:]
        for row in rows {
            let otherID: UUID?
            if row.requesterId == uid {
                otherID = row.addresseeId
            } else if row.addresseeId == uid {
                otherID = row.requesterId
            } else {
                otherID = nil
            }
            if let otherID, rowByOtherID[otherID] == nil {
                rowByOtherID[otherID] = row
            }
        }
        let otherIDs = Array(rowByOtherID.keys)
        let profs = try await fetchProfilesByIDs(otherIDs)
        return rowByOtherID.map { otherID, r in
            return FriendDTO(id: r.id, status: r.status,
                             requesterId: r.requesterId, addresseeId: r.addresseeId,
                             profile: profs[otherID])
        }
        .sorted {
            ($0.profile?.displayName ?? $0.profile?.handle ?? "")
                .localizedCaseInsensitiveCompare(
                    $1.profile?.displayName ?? $1.profile?.handle ?? ""
                ) == .orderedAscending
        }
    }

    /// Outgoing pending requests (where I'm the requester), hydrated with the
    /// addressee's profile.
    func listSentRequests() async -> [FriendDTO] {
        guard let uid = await myUID() else { return [] }
        let rows: [FriendshipDTO] = (try? await client
            .from("friendships")
            .select()
            .eq("requester_id", value: uid.uuidString)
            .eq("status", value: "pending")
            .execute()
            .value) ?? []
        let profs = await profilesByIDs(rows.map(\.addresseeId))
        return rows.map { r in
            FriendDTO(id: r.id, status: r.status,
                      requesterId: r.requesterId, addresseeId: r.addresseeId,
                      profile: profs[r.addresseeId])
        }
    }

    /// Incoming pending requests (where I'm the addressee), hydrated with requester profile.
    func listIncomingRequests() async -> [FriendDTO] {
        guard let uid = await myUID() else { return [] }
        let rows: [FriendshipDTO] = (try? await client
            .from("friendships")
            .select()
            .eq("addressee_id", value: uid.uuidString)
            .eq("status", value: "pending")
            .execute()
            .value) ?? []
        let profs = await profilesByIDs(rows.map(\.requesterId))
        return rows.map { r in
            FriendDTO(id: r.id, status: r.status,
                      requesterId: r.requesterId, addresseeId: r.addresseeId,
                      profile: profs[r.requesterId])
        }
    }

    // MARK: - Now playing & social

    func upsertNowPlaying(trackName: String?,
                          artist: String?,
                          album: String? = nil,
                          albumArt: String? = nil,
                          trackUri: String?,
                          isPlaying: Bool,
                          progressMs: Int?,
                          durationMs: Int?,
                          userID expectedUserID: UUID? = nil) async {
        guard let uid = await myUID(expected: expectedUserID) else { return }
        let row = NowPlayingUpsertDTO(
            userId: uid,
            trackName: trackName,
            artist: artist,
            album: album,
            albumArt: albumArt,
            trackUri: trackUri,
            isPlaying: isPlaying,
            progressMs: progressMs,
            durationMs: durationMs,
            updatedAt: nowISO
        )
        _ = try? await client.from("now_playing")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    /// Remove the viewer's live presence when playback stops or Ghost Mode turns
    /// on. Reads also enforce a TTL in case this final write never reaches server.
    func clearMyNowPlaying(userID expectedUserID: UUID? = nil) async {
        guard let uid = await myUID(expected: expectedUserID) else { return }
        _ = try? await client.from("now_playing")
            .delete()
            .eq("user_id", value: uid.uuidString)
            .execute()
    }

    /// Friends' now-playing snapshots joined with their profiles, newest first.
    func getFriendsNowPlaying() async -> [FriendNowPlayingDTO] {
        (try? await fetchFriendsNowPlaying()) ?? []
    }

    /// Throwing social-feed read so a transient backend failure does not have to
    /// masquerade as "none of your friends are listening."
    func fetchFriendsNowPlaying() async throws -> [FriendNowPlayingDTO] {
        let friends = try await fetchFriends().filter { $0.profile != nil }
        let ids = friends.compactMap { $0.profile?.userId }
        guard !ids.isEmpty else { return [] }
        let rows: [NowPlayingRowDTO] = try await client
            .from("now_playing")
            .select()
            .in("user_id", values: ids.map(\.uuidString))
            .execute()
            .value
        let liveRows = rows.filter {
            FriendActivityPolicy.isLive(
                isPlaying: $0.isPlaying,
                trackName: $0.trackName,
                updatedAt: $0.updatedAt
            )
        }
        let npMap = Dictionary(liveRows.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
        return friends.compactMap { f -> FriendNowPlayingDTO? in
            guard let prof = f.profile else { return nil }
            guard let np = npMap[prof.userId],
                  let updatedAt = np.updatedAt else { return nil }
            return FriendNowPlayingDTO(
                userId: prof.userId,
                displayName: prof.displayName,
                avatarUrl: prof.avatarUrl,
                trackName: np.trackName,
                artist: np.artist,
                albumArt: np.albumArt,
                isPlaying: true,
                updatedAt: updatedAt
            )
        }
        .sorted { ($0.updatedAt) > ($1.updatedAt) }
    }

    /// Record one track play for the leaderboard. Best-effort.
    func logPlay(trackUri: String?,
                 trackName: String?,
                 artist: String?,
                 durationMs: Int?,
                 albumArt: String? = nil,
                 userID expectedUserID: UUID? = nil) async -> Bool {
        guard let uid = await myUID(expected: expectedUserID) else { return false }
        let row = PlayLogInsertDTO(
            userId: uid,
            trackUri: trackUri,
            trackName: trackName,
            artist: artist,
            durationMs: durationMs ?? 0,
            albumArt: albumArt
        )
        do {
            try await client.from("play_log").insert(row).execute()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Play history & leaderboards

    func fetchPlayHistory(limit: Int = 100, userID: UUID? = nil) async -> [PlayEntryDTO] {
        guard let uid = await myUID(expected: userID) else { return [] }
        let rows: [PlayEntryDTO] = (try? await client
            .from("play_log")
            .select("id, track_uri, track_name, artist, duration_ms, played_at, album_art")
            .eq("user_id", value: uid.uuidString)
            .order("played_at", ascending: false)
            .limit(limit)
            .execute()
            .value) ?? []
        return rows
    }

    /// Fetch the account's complete observed play history in deterministic pages.
    /// Personal stats aggregate these events locally; a single oversized request
    /// can otherwise be silently capped by PostgREST's server row limit.
    func fetchAllPlayHistory(
        pageSize: Int = 500,
        maxRows: Int = 50_000
    ) async -> [PlayEntryDTO]? {
        guard let uid = await myUID(), pageSize > 0, maxRows > 0 else {
            return nil
        }
        var rows: [PlayEntryDTO] = []
        var offset = 0
        do {
            while rows.count < maxRows {
                let remaining = maxRows - rows.count
                let requested = min(pageSize, remaining)
                let page: [PlayEntryDTO] = try await client
                    .from("play_log")
                    .select("id, track_uri, track_name, artist, duration_ms, played_at, album_art")
                    .eq("user_id", value: uid.uuidString)
                    .order("played_at", ascending: false)
                    .order("id", ascending: false)
                    .range(from: offset, to: offset + requested - 1)
                    .execute()
                    .value
                rows.append(contentsOf: page)
                if page.count < requested { break }
                offset += page.count
            }
            return rows
        } catch {
            // A partial history produces incorrect counts. Callers preserve the
            // last-good cache unless every requested page succeeds.
            return nil
        }
    }

    func deletePlayEntries(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await client.from("play_log")
            .delete()
            .in("id", values: ids.map(\.uuidString))
            .execute()
    }

    func clearPlayHistory() async throws {
        guard let uid = await myUID() else { return }
        try await client.rpc("clear_my_listening_history", params: ["expected_owner": uid.uuidString]).execute()
    }

    // MARK: - Friend activity

    /// Accepted friends' durable listening events, newest first. The server owns
    /// relationship authorization and returns aggregate reactions in the same
    /// snapshot so clients do not fan out one request per activity.
    func fetchFriendActivity(
        limit: Int = 50,
        before cursor: FriendActivityCursor? = nil
    ) async throws -> [FriendActivityEntryDTO] {
        guard await myUID() != nil else { throw BackendError.notSignedIn }
        var params: [String: AnyJSON] = [
            "p_limit": .integer(max(1, min(limit, 100)))
        ]
        if let cursor {
            params["p_before_played_at"] = .string(cursor.playedAt)
            params["p_before_id"] = .string(cursor.activityID.uuidString)
        }
        return try await client
            .rpc("friend_activity_feed", params: params)
            .execute()
            .value
    }

    /// Set or remove the viewer's one reaction for a friend's activity.
    /// RLS remains the final boundary if a friendship changed after the feed read.
    func setFriendActivityReaction(
        activityID: UUID,
        reaction: FriendActivityReaction?
    ) async throws {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        if let reaction {
            let row = FriendActivityReactionUpsertDTO(
                activityId: activityID,
                userId: uid,
                reaction: reaction
            )
            try await client
                .from("friend_activity_reactions")
                .upsert(row, onConflict: "activity_id,user_id")
                .execute()
        } else {
            try await client
                .from("friend_activity_reactions")
                .delete()
                .eq("activity_id", value: activityID.uuidString)
                .eq("user_id", value: uid.uuidString)
                .execute()
        }
    }

    func getSongLeaderboard(windowDays: Int) async -> [SongLeaderboardEntryDTO] {
        (try? await client
            .rpc("song_leaderboard", params: ["window_days": AnyJSON.integer(windowDays)])
            .execute()
            .value) ?? []
    }

    func getFriendLeaderboard(windowDays: Int) async -> [LeaderboardEntryDTO] {
        (try? await client
            .rpc("friend_leaderboard", params: ["window_days": AnyJSON.integer(windowDays)])
            .execute()
            .value) ?? []
    }

    // MARK: - Track weights

    func getMyWeights(userID expectedUserID: UUID? = nil) async -> [TrackWeightDTO] {
        guard let uid = await myUID(expected: expectedUserID) else { return [] }
        let rows: [TrackWeightDTO] = (try? await client
            .from("track_weights")
            .select("track_uri, weight")
            .eq("user_id", value: uid.uuidString)
            .execute()
            .value) ?? []
        return rows
    }

    func setTrackWeight(
        uri: String,
        weight: Double,
        userID expectedUserID: UUID? = nil
    ) async throws {
        guard let uid = await myUID(expected: expectedUserID) else {
            throw BackendError.notSignedIn
        }
        let row = TrackWeightUpsertDTO(userId: uid, trackUri: uri, weight: weight)
        try await client.from("track_weights")
            .upsert(row, onConflict: "user_id,track_uri")
            .execute()
    }

    // MARK: - Skip versions

    func listSkipVersions(trackUri: String) async -> [TrackSkipVersionDTO] {
        let rows: [TrackSkipVersionDTO] = (try? await client
            .from("track_skip_versions")
            .select()
            .eq("spotify_track_uri", value: trackUri)
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []
        return rows
    }

    func getActiveSkipVersion(trackUri: String) async -> TrackSkipVersionDTO? {
        let rows: [TrackSkipVersionDTO] = (try? await client
            .from("track_skip_versions")
            .select()
            .eq("spotify_track_uri", value: trackUri)
            .eq("is_active", value: true)
            .limit(1)
            .execute()
            .value) ?? []
        return rows.first
    }

    @discardableResult
    func createSkipVersion(trackUri: String,
                           label: String,
                           skipRegions: [SkipRegion]) async throws -> TrackSkipVersionDTO? {
        let payload = SkipVersionInsertDTO(spotifyTrackUri: trackUri, label: label, skipRegions: skipRegions)
        let rows: [TrackSkipVersionDTO] = try await client
            .from("track_skip_versions")
            .insert(payload)
            .select()
            .execute()
            .value
        return rows.first
    }

    func updateSkipVersion(id: UUID,
                           label: String? = nil,
                           skipRegions: [SkipRegion]? = nil) async throws {
        var row = SkipVersionUpdateDTO()
        row.label = label
        row.skipRegions = skipRegions
        try await client.from("track_skip_versions")
            .update(row)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteSkipVersion(id: UUID) async {
        _ = try? await client.from("track_skip_versions")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Make `id` the active version for its track (clears others first).
    func setActiveSkipVersion(id: UUID, trackUri: String, active: Bool) async throws {
        try await client.from("track_skip_versions")
            .update(SkipVersionActiveDTO(isActive: false))
            .eq("spotify_track_uri", value: trackUri)
            .execute()
        if active {
            try await client.from("track_skip_versions")
                .update(SkipVersionActiveDTO(isActive: true))
                .eq("id", value: id.uuidString)
                .execute()
        }
    }

    // MARK: - Playlist folders

    func listFolders() async -> [FolderDTO] {
        let rows: [FolderRowDTO] = (try? await client
            .from("playlist_folders")
            .select("id, name, playlist_folder_items(count)")
            .order("sort", ascending: true)
            .order("created_at", ascending: true)
            .execute()
            .value) ?? []
        return rows.map {
            FolderDTO(id: $0.id, name: $0.name, itemCount: $0.playlistFolderItems?.first?.count ?? 0)
        }
    }

    @discardableResult
    func createFolder(name: String) async throws -> FolderDTO {
        guard let owner = await myUID() else { throw BackendError.message("Sign in to create folders.") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = FolderInsertDTO(owner: owner, name: trimmed.isEmpty ? "New Folder" : trimmed)
        let rows: [FolderRowDTO] = try await client
            .from("playlist_folders")
            .insert(payload)
            .select("id, name")
            .execute()
            .value
        guard let r = rows.first else { throw BackendError.message("Folder insert returned no row.") }
        return FolderDTO(id: r.id, name: r.name, itemCount: 0)
    }

    func renameFolder(id: UUID, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.from("playlist_folders")
            .update(FolderRenameDTO(name: trimmed.isEmpty ? "Folder" : trimmed))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteFolder(id: UUID) async throws {
        try await client.from("playlist_folders")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func listFolderItems(folderID: UUID) async -> [FolderItemDTO] {
        let rows: [FolderItemDTO] = (try? await client
            .from("playlist_folder_items")
            .select("playlist_key, provider_id, playlist_id, name, image, owner_name, track_count")
            .eq("folder_id", value: folderID.uuidString)
            .order("added_at", ascending: true)
            .execute()
            .value) ?? []
        return rows
    }

    func addPlaylistToFolder(folderID: UUID,
                             key: String,
                             providerId: ProviderID,
                             playlistId: String,
                             name: String,
                             image: String? = nil,
                             ownerName: String? = nil,
                             trackCount: Int) async throws {
        let payload = FolderItemInsertDTO(
            folderId: folderID,
            playlistKey: key,
            providerId: providerId.rawValue,
            playlistId: playlistId,
            name: name,
            image: image,
            ownerName: ownerName,
            trackCount: trackCount
        )
        try await client.from("playlist_folder_items")
            .upsert(payload, onConflict: "folder_id,playlist_key")
            .execute()
    }

    func removePlaylistFromFolder(folderID: UUID, key: String) async throws {
        try await client.from("playlist_folder_items")
            .delete()
            .eq("folder_id", value: folderID.uuidString)
            .eq("playlist_key", value: key)
            .execute()
    }

    /// Folder ids that already contain a given playlist key.
    func foldersContainingPlaylist(key: String) async -> [String] {
        let rows: [FolderIdRowDTO] = (try? await client
            .from("playlist_folder_items")
            .select("folder_id")
            .eq("playlist_key", value: key)
            .execute()
            .value) ?? []
        return rows.map { $0.folderId.uuidString }
    }

    // MARK: - Mixtapes

    func listMixtapes() async -> MixtapeListDTO {
        let uid = await myUID()
        var all: [MixtapeDTO] = (try? await client
            .from("mixtapes")
            .select()
            .order("updated_at", ascending: false)
            .execute()
            .value) ?? []
        for i in all.indices {
            all[i].mine = (uid != nil && all[i].owner == uid)
            all[i].coverUrl = await mixtapeMediaDisplayURL(all[i].coverUrl)
        }
        return MixtapeListDTO(mine: all.filter { $0.mine }, shared: all.filter { !$0.mine })
    }

    func getMixtape(id: UUID) async -> MixtapeDetailDTO? {
        let uid = await myUID()
        let mixtapes: [MixtapeDTO] = (try? await client
            .from("mixtapes")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value) ?? []
        guard var mixtape = mixtapes.first else { return nil }
        mixtape.mine = (uid != nil && mixtape.owner == uid)
        mixtape.coverUrl = await mixtapeMediaDisplayURL(mixtape.coverUrl)
        guard var tracks: [MixtapeTrackDTO] = try? await client
            .from("mixtape_tracks")
            .select()
            .eq("mixtape_id", value: id.uuidString)
            .order("position", ascending: true)
            .execute()
            .value else { return nil }
        for index in tracks.indices {
            tracks[index].noteImageUrl = await mixtapeMediaDisplayURL(tracks[index].noteImageUrl)
        }
        return MixtapeDetailDTO(mixtape: mixtape, tracks: tracks)
    }

    /// Create a mixtape, stamping owner from the live session (mirrors RN).
    @discardableResult
    func createMixtape(title: String, recipientID: UUID? = nil) async throws -> UUID? {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        let rows: [IdRowDTO] = try await client
            .from("mixtapes")
            .insert(MixtapeInsertDTO(title: title, owner: uid, recipientId: recipientID))
            .select("id")
            .execute()
            .value
        return rows.first?.id
    }

    func updateMixtape(id: UUID,
                       title: String? = nil,
                       description: String? = nil,
                       coverUrl: String?? = nil) async throws {
        var row = MixtapeUpdateDTO(updatedAt: nowISO)
        row.title = title
        row.description = description
        if case let .some(value) = coverUrl { row.coverUrl = value }
        try await client.from("mixtapes")
            .update(row)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteMixtape(id: UUID) async {
        _ = try? await client.from("mixtapes")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func addMixtapeTrack(mixtapeID: UUID,
                         trackUri: String,
                         trackName: String,
                         artist: String,
                         albumArt: String?,
                         durationMs: Int?) async throws {
        // Append after the current max position.
        struct PositionRow: Decodable { let position: Int? }
        let last: [PositionRow] = try await client
            .from("mixtape_tracks")
            .select("position")
            .eq("mixtape_id", value: mixtapeID.uuidString)
            .order("position", ascending: false)
            .limit(1)
            .execute()
            .value
        let pos = (last.first?.position ?? -1) + 1
        let payload = MixtapeTrackInsertDTO(
            mixtapeId: mixtapeID,
            position: pos,
            trackUri: trackUri,
            trackName: trackName,
            artist: artist,
            albumArt: albumArt,
            durationMs: durationMs
        )
        try await client.from("mixtape_tracks").insert(payload).execute()
    }

    func updateMixtapeTrack(id: UUID,
                            skipRegions: [SkipRegion]? = nil,
                            note: String? = nil,
                            noteImageUrl: String?? = nil,
                            position: Int? = nil) async throws {
        var row = MixtapeTrackUpdateDTO()
        row.skipRegions = skipRegions
        row.note = note
        if case let .some(value) = noteImageUrl { row.noteImageUrl = value }
        row.position = position
        try await client.from("mixtape_tracks")
            .update(row)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteMixtapeTrack(id: UUID) async {
        _ = try? await client.from("mixtape_tracks")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Update positions of multiple tracks. NOTE: RN issues these in parallel;
    /// here they run sequentially to stay simple and avoid an unstructured task group.
    func reorderMixtapeTracks(_ ordered: [(id: UUID, position: Int)]) async {
        for o in ordered {
            var row = MixtapeTrackUpdateDTO()
            row.position = o.position
            _ = try? await client.from("mixtape_tracks")
                .update(row)
                .eq("id", value: o.id.uuidString)
                .execute()
        }
    }

    func shareMixtape(id: UUID, friendID: UUID) async throws {
        let row = MixtapeShareDTO(mixtapeId: id, sharedWith: friendID)
        try await client.from("mixtape_shares")
            .upsert(row, onConflict: "mixtape_id,shared_with")
            .execute()
    }

    func sendMixtapeGift(id: UUID, friendID: UUID, expectedOwner: UUID) async throws {
        guard await myUID() == expectedOwner else { throw BackendError.notSignedIn }
        try await client.rpc("send_mixtape_gift", params: [
            "expected_owner": expectedOwner.uuidString,
            "target_mixtape": id.uuidString,
            "target_friend": friendID.uuidString
        ]).execute()
    }

    func listMixtapeShares(id: UUID) async -> [UUID] {
        let rows: [MixtapeShareRowDTO] = (try? await client
            .from("mixtape_shares")
            .select("shared_with")
            .eq("mixtape_id", value: id.uuidString)
            .execute()
            .value) ?? []
        return rows.map { $0.sharedWith }
    }

    func unshareMixtape(id: UUID, friendID: UUID) async {
        _ = try? await client.from("mixtape_shares")
            .delete()
            .eq("mixtape_id", value: id.uuidString)
            .eq("shared_with", value: friendID.uuidString)
            .execute()
    }

    // MARK: - Snapshots / backups

    func renameSnapshot(id: UUID, name: String) async throws -> LibrarySnapshotDTO {
        let name = try BackupName.validated(name)
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        let row: LibrarySnapshotDTO = try await client.from("library_snapshots")
            .update(["name": name])
            .eq("id", value: id.uuidString)
            .eq("owner", value: uid.uuidString)
            .select("id, name, playlist_count, track_count, liked_count, created_at, providers")
            .single()
            .execute().value
        guard await myUID(expected: uid) != nil else { throw BackendError.notSignedIn }
        return row
    }

    /// A missing/failed profile read is not permission to create a new baseline.
    /// Existing snapshots also count, including ones created on another device.
    func needsInitialBackup(userID: UUID) async throws -> Bool {
        guard await myUID(expected: userID) != nil else { throw BackendError.notSignedIn }
        struct Marker: Decodable { let initial_backup_at: String? }
        let marker: Marker = try await client.from("profiles")
            .select("initial_backup_at")
            .eq("user_id", value: userID.uuidString)
            .single().execute().value
        if marker.initial_backup_at != nil { return false }
        let existing: [IdRowDTO] = try await client.from("library_snapshots")
            .select("id").eq("owner", value: userID.uuidString)
            .limit(1).execute().value
        if !existing.isEmpty {
            try await markInitialBackupCompleted(userID: userID)
            return false
        }
        return true
    }

    func markInitialBackupCompleted(userID: UUID) async throws {
        guard await myUID(expected: userID) != nil else { throw BackendError.notSignedIn }
        try await client.from("profiles")
            .update(["initial_backup_at": nowISO])
            .eq("user_id", value: userID.uuidString)
            .is("initial_backup_at", value: nil)
            .execute()
    }

    func fetchSnapshots() async -> [LibrarySnapshotDTO] {
        guard let uid = await myUID() else { return [] }
        let rows: [LibrarySnapshotDTO] = (try? await client
            .from("library_snapshots")
            .select("id, name, playlist_count, track_count, liked_count, created_at, providers")
            .eq("owner", value: uid.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []
        return rows
    }

    func deleteSnapshot(id: UUID) async -> Bool {
        do {
            try await client.from("library_snapshots")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            return true
        } catch {
            return false
        }
    }

    func fetchSnapshotPlaylists(snapshotID: UUID) async -> [SnapshotPlaylistDTO] {
        (try? await requireSnapshotPlaylists(snapshotID: snapshotID)) ?? []
    }

    func fetchSnapshotTracks(snapshotPlaylistID: UUID) async -> [SnapshotTrackDTO] {
        (try? await requireSnapshotTracks(snapshotPlaylistID: snapshotPlaylistID)) ?? []
    }

    func fetchSnapshotLikedTracks(snapshotID: UUID) async -> [SnapshotLikedTrackDTO] {
        (try? await requireSnapshotLikedTracks(snapshotID: snapshotID)) ?? []
    }

    func requireSnapshotPlaylists(snapshotID: UUID) async throws -> [SnapshotPlaylistDTO] {
        try await snapshotRows(table: "snapshot_playlists",
            columns: "id, spotify_playlist_id, name, description, image_url, owner_name, track_count",
            key: "snapshot_id", id: snapshotID)
    }

    func requireSnapshotTracks(snapshotPlaylistID: UUID) async throws -> [SnapshotTrackDTO] {
        try await snapshotRows(table: "snapshot_tracks",
            columns: "spotify_track_uri, track_name, artist_name, album_name, album_art_url, duration_ms, position",
            key: "snapshot_playlist_id", id: snapshotPlaylistID, order: "position")
    }

    func requireSnapshotLikedTracks(snapshotID: UUID) async throws -> [SnapshotLikedTrackDTO] {
        try await snapshotRows(table: "snapshot_liked_tracks",
            columns: "spotify_track_uri, track_name, artist_name, album_name, album_art_url, duration_ms, added_at, position",
            key: "snapshot_id", id: snapshotID, order: "position")
    }

    /// Every page must succeed before returning an inventory. A failed or
    /// truncated read must never be interpreted as songs being removed.
    private func snapshotRows<T: Decodable & Sendable>(
        table: String, columns: String, key: String, id: UUID, order: String = "id"
    ) async throws -> [T] {
        var rows: [T] = []
        let pageSize = 500
        while true {
            try Task.checkCancellation()
            let page: [T] = try await client.from(table).select(columns)
                .eq(key, value: id.uuidString)
                .order(order, ascending: true)
                .order("id", ascending: true)
                .range(from: rows.count, to: rows.count + pageSize - 1)
                .execute().value
            rows.append(contentsOf: page)
            if page.count < pageSize { return rows }
        }
    }

    /// Body for the `snapshot-library` edge function.
    private struct CreateSnapshotBody: Encodable {
        let spotifyToken: String
        let name: String
        let supabaseAccessToken: String
    }

    /// Capture a fresh Spotify snapshot via the `snapshot-library` edge function.
    func createSnapshot(spotifyToken: String, name: String? = nil) async throws -> CreateSnapshotResultDTO {
        let token = try await requireAccessToken()
        let body = CreateSnapshotBody(spotifyToken: spotifyToken, name: name ?? "", supabaseAccessToken: token)
        do {
            return try await client.functions
                .invoke("snapshot-library", options: .init(body: body))
        } catch {
            throw edgeError(error)
        }
    }

    /// Body for the `restore-snapshot` edge function.
    private struct RestoreSnapshotBody: Encodable {
        let spotifyToken: String
        let snapshotId: String
        let supabaseAccessToken: String
    }

    /// Restore a snapshot to Spotify via the `restore-snapshot` edge function.
    func restoreSnapshot(spotifyToken: String, snapshotID: UUID) async throws -> RestoreSnapshotResultDTO {
        let token = try await requireAccessToken()
        let body = RestoreSnapshotBody(
            spotifyToken: spotifyToken,
            snapshotId: snapshotID.uuidString,
            supabaseAccessToken: token
        )
        do {
            return try await client.functions
                .invoke("restore-snapshot", options: .init(body: body))
        } catch {
            throw edgeError(error)
        }
    }

    /// Unwrap a structured `{ "error": "..." }` body from an edge-function failure
    /// (`FunctionsError.httpError`) into a readable `BackendError`, so the UI can
    /// show the real cause (e.g. "Not signed in", "Spotify 401") instead of a
    /// generic "try again". Falls back to the original error otherwise.
    private func edgeError(_ error: Error) -> Error {
        guard case let FunctionsError.httpError(_, data) = error,
              let payload = try? JSONDecoder().decode(EdgeErrorDTO.self, from: data),
              let message = payload.error, !message.isEmpty
        else { return error }
        return BackendError.message(message)
    }

    private struct AppleMusicTokenDTO: Decodable {
        let token: String
        let expiresAt: Double?  // epoch seconds
        let error: String?
    }

    /// Fetch a fresh Apple Music developer token (ES256 JWT) from the
    /// `apple-music-token` edge function, which signs it server-side from the
    /// MusicKit .p8 secret. Used to authorize Apple Music REST (catalog) requests.
    func appleMusicDeveloperToken() async throws -> (token: String, expiresAt: Date) {
        _ = try await requireAccessToken() // function requires a valid Supabase session
        let res: AppleMusicTokenDTO = try await client.functions
            .invoke("apple-music-token", options: .init(body: [String: String]()))
        if let err = res.error { throw BackendError.message(err) }
        let expiry = res.expiresAt.map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(60 * 60 * 24 * 30)
        return (res.token, expiry)
    }

    private func requireAccessToken() async throws -> String {
        guard let token = try? await client.auth.session.accessToken else {
            throw BackendError.notSignedIn
        }
        return token
    }

    // MARK: - Account / data management

    /// Delete generated music data while preserving the user's Heartable identity,
    /// friends, and paired music services. Every operation throws on failure so
    /// the UI never reports a partially completed wipe as success.
    func deleteAllUserData(userID expectedUserID: UUID) async throws {
        guard let uid = await myUID(expected: expectedUserID) else { throw BackendError.notSignedIn }
        let uidStr = uid.uuidString

        // Storage cannot participate in the Postgres transaction. Clean this
        // account's media first; failure leaves database rows intact and retryable.
        try await removeStorageFolder(bucket: "mixtape-media", path: uidStr.lowercased())
        try await removeStorageFolder(bucket: "mixtape-gifts", path: uidStr.lowercased())
        guard await myUID(expected: uid) != nil else { throw BackendError.notSignedIn }
        // One transaction and verified cascades: no paginated ID reads or
        // giant DELETE URLs. The server independently verifies expected_owner.
        try await client.rpc("clear_my_music_data", params: ["expected_owner": uidStr])
            .execute()
    }

    private func removeStorageFolder(bucket: String, path: String) async throws {
        let storage = client.storage.from(bucket)
        while true {
            let files = try await storage.list(
                path: path,
                options: SearchOptions(limit: 100)
            )
            guard !files.isEmpty else { return }
            // New gift media is nested by mixtape. Storage returns virtual
            // folders without an ID; deleting that folder name does not recurse.
            for folder in files where folder.id == nil {
                try await removeStorageFolder(bucket: bucket, path: "\(path)/\(folder.name)")
            }
            let objectPaths = files.filter { $0.id != nil }.map { "\(path)/\($0.name)" }
            if !objectPaths.isEmpty { try await storage.remove(paths: objectPaths) }
            if files.count < 100 { return }
        }
    }

    private struct DeleteAccountResultDTO: Decodable {
        let ok: Bool?
        let error: String?
    }

    /// Permanently delete the signed-in account: every owned row, storage objects,
    /// and the `auth.users` record itself, via the `delete-account` edge function
    /// (service role). The client attaches the session bearer token automatically;
    /// the function verifies it and only deletes that user's own data. After this
    /// returns, the local session is dead, so the caller should sign out.
    func deleteAccount() async throws {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        // The legacy account-deletion function predates private gift media.
        // Remove this account's nested uploads while its Storage policies still
        // authorize them, before the auth record is deleted server-side.
        try await removeStorageFolder(bucket: "mixtape-gifts", path: uid.uuidString.lowercased())
        guard await myUID(expected: uid) != nil else { throw BackendError.notSignedIn }
        _ = try await requireAccessToken() // surface a clean "Not signed in" if there's no session
        let res: DeleteAccountResultDTO = try await client.functions
            .invoke("delete-account", options: .init(body: [String: String]()))
        if let err = res.error { throw BackendError.message(err) }
    }

    // MARK: - Storage (image uploads)

    /// Upload a JPEG to the public `avatars` bucket under the user's folder and
    /// return its public URL string. Callers then persist the URL via
    /// `updateMyProfile(avatarUrl:)`.
    func uploadAvatar(_ data: Data) async throws -> String {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        // Stable path (one file per user, lowercased to match auth.uid()), upsert
        // to overwrite — no accumulation. Cache-bust the returned URL so
        // AsyncImage refetches the new image instead of showing the cached one.
        let path = "\(uid.uuidString.lowercased())/avatar.jpg"
        _ = try await client.storage
            .from("avatars")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let url = try client.storage.from("avatars").getPublicURL(path: path)
        return url.absoluteString + "?t=\(Int(Date().timeIntervalSince1970))"
    }

    /// Immutable private media avoids stale artwork on replacement. Persist the
    /// reference, not the expiring signed URL used for display.
    func uploadMixtapeImage(mixtapeID: UUID, _ data: Data) async throws -> String {
        guard let uid = await myUID() else { throw BackendError.notSignedIn }
        let path = "\(uid.uuidString.lowercased())/\(mixtapeID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.storage
            .from("mixtape-gifts")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        return "heartable-media://mixtape-gifts/\(path)"
    }

    func mixtapeMediaDisplayURL(_ reference: String?) async -> String? {
        guard let reference, !reference.isEmpty else { return nil }
        guard let path = MixtapeMediaReference.path(from: reference) else {
            return reference.hasPrefix("https://") ? reference : nil
        }
        return try? await client.storage.from("mixtape-gifts")
            .createSignedURL(path: path, expiresIn: 3600).absoluteString
    }
}

/// Errors surfaced from backend mutations (reads swallow and return empty/nil).
enum BackendError: Error, LocalizedError {
    case notSignedIn
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .message(let m): return m
        }
    }
}

// MARK: - Friend activity repository

/// Injectable backend seam for the activity repository. Production uses
/// `BackendAPI`; tests can supply deterministic closures without Supabase.
struct FriendActivityClient: Sendable {
    var fetch:
        @Sendable (Int, FriendActivityCursor?) async throws
            -> [FriendActivityEntryDTO]
    var setReaction:
        @Sendable (UUID, FriendActivityReaction?) async throws
            -> Void

    static let live = FriendActivityClient(
        fetch: { limit, cursor in
            try await BackendAPI.shared.fetchFriendActivity(
                limit: limit,
                before: cursor
            )
        },
        setReaction: { activityID, reaction in
            try await BackendAPI.shared.setFriendActivityReaction(
                activityID: activityID,
                reaction: reaction
            )
        }
    )
}

/// Account-scoped stale-while-revalidate store for the historical friends feed.
///
/// `load` publishes a disk or memory snapshot before revalidating it. A failed
/// refresh never replaces that last-good snapshot with an empty feed. Reactions
/// update optimistically, with a rollback when the server rejects the mutation.
@MainActor
@Observable
final class FriendActivityRepository {
    private struct DiskSnapshot: Codable, Sendable {
        static let currentVersion = 1

        let version: Int
        let ownerID: UUID
        let entries: [FriendActivityEntryDTO]
        let fetchedAt: Date
    }

    private actor CacheIO {
        func load(from url: URL, ownerID: UUID) -> DiskSnapshot? {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(
                      DiskSnapshot.self,
                      from: data
                  ),
                  snapshot.version == DiskSnapshot.currentVersion,
                  snapshot.ownerID == ownerID else {
                return nil
            }
            return snapshot
        }

        func save(_ snapshot: DiskSnapshot, to url: URL) {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    nonisolated static let freshnessWindow: TimeInterval = 2 * 60

    private let client: FriendActivityClient
    private let cacheIO = CacheIO()
    private var hydratedOwnerID: UUID?
    private var lifecycleID = UUID()

    private(set) var entries: [FriendActivityEntryDTO] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = true
    private(set) var reactingActivityIDs: Set<UUID> = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    init(client: FriendActivityClient = .live) {
        self.client = client
    }

    /// Current memory snapshot. This never initiates network work.
    func cached(limit: Int = 50) -> [FriendActivityEntryDTO] {
        Array(entries.prefix(max(0, limit)))
    }

    /// Serve the account's disk/memory snapshot first, then revalidate only when
    /// stale. Awaiting this method waits for revalidation, but observers receive
    /// hydrated entries as soon as disk decoding completes.
    func load(limit: Int = 50, now: Date = Date()) async {
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            reset()
            return
        }
        await hydrate(ownerID: ownerID)
        guard hydratedOwnerID == ownerID else { return }
        guard Self.shouldRefresh(lastUpdated: lastUpdated, now: now, force: false)
        else { return }
        await refresh(limit: limit)
    }

    /// Force a first-page network refresh while retaining the last-good page on
    /// failure. This is the pull-to-refresh contract for a future feed surface.
    func refresh(limit: Int = 50) async {
        guard !isRefreshing,
              let ownerID = AccountSessionStore.currentOwnerID else {
            return
        }
        if hydratedOwnerID != ownerID {
            await hydrate(ownerID: ownerID)
        }
        guard hydratedOwnerID == ownerID else { return }

        let requestLifecycleID = lifecycleID
        isLoading = entries.isEmpty
        isRefreshing = !entries.isEmpty
        errorMessage = nil
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let requested = max(1, min(limit, 100))
            let fetched = try await client.fetch(requested, nil)
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            entries = Self.unique(fetched)
            canLoadMore = fetched.count == requested
            lastUpdated = Date()
            await persist(ownerID: ownerID)
        } catch {
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch the next keyset page. Existing entries are never discarded if that
    /// request fails, and duplicate ids are removed defensively.
    func loadMore(limit: Int = 50) async {
        guard !isLoadingMore,
              canLoadMore,
              !entries.isEmpty,
              let cursor = entries.last?.cursor,
              let ownerID = AccountSessionStore.currentOwnerID,
              hydratedOwnerID == ownerID else {
            return
        }
        let requestLifecycleID = lifecycleID
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let requested = max(1, min(limit, 100))
            let fetched = try await client.fetch(requested, cursor)
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            entries = Self.unique(entries + fetched)
            canLoadMore = fetched.count == requested
            await persist(ownerID: ownerID)
        } catch {
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Selecting the active reaction removes it; selecting another replaces it.
    /// Counts and viewer state change immediately, then roll back if RLS or the
    /// network rejects the authoritative mutation.
    func toggleReaction(
        activityID: UUID,
        reaction: FriendActivityReaction
    ) async {
        guard !reactingActivityIDs.contains(activityID),
              let index = entries.firstIndex(where: { $0.id == activityID }),
              let ownerID = AccountSessionStore.currentOwnerID,
              hydratedOwnerID == ownerID else {
            return
        }
        let requestLifecycleID = lifecycleID
        let previous = entries[index]
        let nextReaction =
            previous.viewerReaction == reaction ? nil : reaction
        entries[index] = Self.applyingReaction(nextReaction, to: previous)
        reactingActivityIDs.insert(activityID)
        errorMessage = nil

        do {
            try await client.setReaction(activityID, nextReaction)
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            await persist(ownerID: ownerID)
        } catch {
            guard ownsCurrentLifecycle(
                ownerID: ownerID,
                requestLifecycleID: requestLifecycleID
            ) else { return }
            if let rollbackIndex = entries.firstIndex(where: {
                $0.id == activityID
            }) {
                entries[rollbackIndex] = previous
            }
            errorMessage = error.localizedDescription
        }
        guard ownsCurrentLifecycle(
            ownerID: ownerID,
            requestLifecycleID: requestLifecycleID
        ) else { return }
        reactingActivityIDs.remove(activityID)
    }

    /// Clears in-memory identity on sign-out/account transition. Account-scoped
    /// disk snapshots cannot be read by another Heartable account.
    func reset() {
        lifecycleID = UUID()
        hydratedOwnerID = nil
        entries = []
        isLoading = false
        isRefreshing = false
        isLoadingMore = false
        canLoadMore = true
        reactingActivityIDs = []
        lastUpdated = nil
        errorMessage = nil
    }

    nonisolated static func shouldRefresh(
        lastUpdated: Date?,
        now: Date = Date(),
        force: Bool
    ) -> Bool {
        if force { return true }
        guard let lastUpdated else { return true }
        let age = now.timeIntervalSince(lastUpdated)
        return age < 0 || age >= freshnessWindow
    }

    nonisolated static func applyingReaction(
        _ reaction: FriendActivityReaction?,
        to entry: FriendActivityEntryDTO
    ) -> FriendActivityEntryDTO {
        var updated = entry
        if let previous = updated.viewerReaction {
            let key = previous.rawValue
            let count = max(0, (updated.reactionCounts[key] ?? 0) - 1)
            if count == 0 {
                updated.reactionCounts.removeValue(forKey: key)
            } else {
                updated.reactionCounts[key] = count
            }
        }
        if let reaction {
            updated.reactionCounts[reaction.rawValue, default: 0] += 1
        }
        updated.viewerReaction = reaction
        return updated
    }

    private func hydrate(ownerID: UUID) async {
        guard hydratedOwnerID != ownerID else { return }
        reset()
        let requestLifecycleID = lifecycleID
        guard let url = Self.cacheURL(ownerID: ownerID) else {
            hydratedOwnerID = ownerID
            return
        }
        let snapshot = await cacheIO.load(from: url, ownerID: ownerID)
        guard AccountSessionStore.currentOwnerID == ownerID,
              lifecycleID == requestLifecycleID else {
            return
        }
        if let snapshot {
            entries = Self.unique(snapshot.entries)
            lastUpdated = snapshot.fetchedAt
        }
        hydratedOwnerID = ownerID
    }

    private func persist(ownerID: UUID) async {
        guard hydratedOwnerID == ownerID,
              AccountSessionStore.currentOwnerID == ownerID,
              let lastUpdated,
              let url = Self.cacheURL(ownerID: ownerID) else {
            return
        }
        let snapshot = DiskSnapshot(
            version: DiskSnapshot.currentVersion,
            ownerID: ownerID,
            entries: entries,
            fetchedAt: lastUpdated
        )
        await cacheIO.save(snapshot, to: url)
    }

    private func ownsCurrentLifecycle(
        ownerID: UUID,
        requestLifecycleID: UUID
    ) -> Bool {
        lifecycleID == requestLifecycleID
            && hydratedOwnerID == ownerID
            && AccountSessionStore.currentOwnerID == ownerID
    }

    private nonisolated static func unique(
        _ entries: [FriendActivityEntryDTO]
    ) -> [FriendActivityEntryDTO] {
        var seen = Set<UUID>()
        return entries.filter { seen.insert($0.id).inserted }
    }

    private nonisolated static func cacheURL(ownerID: UUID) -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
            .appendingPathComponent(
                AccountSessionStore.scopedFilename(
                    "friend-activity",
                    ext: "json",
                    ownerID: ownerID
                )
            )
    }
}
