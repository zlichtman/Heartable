import Foundation

/// Codable row payloads for the reused Supabase schema. snake_case columns are
/// mapped explicitly so we don't depend on a global key-decoding strategy.
/// More DTOs are added by their feature phases.

struct ProfileDTO: Codable, Sendable, Identifiable {
    let userId: UUID
    var spotifyId: String?
    var displayName: String?
    var avatarUrl: String?
    var handle: String?
    var shareCode: String?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case spotifyId = "spotify_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case handle
        case shareCode = "share_code"
    }
}

/// Public, user-curated profile content persisted as one JSON object in the
/// existing public profile-media namespace (`avatars/{uid}/profile-curation.json`).
/// Keeping the versioned document separate from `profiles` avoids coupling UI
/// iteration to a database-column rollout while remaining readable by friends.
struct ProfileCurationDTO: Codable, Sendable, Equatable {
    static let currentVersion = 2
    static let oldestSupportedVersion = 1

    var version: Int = currentVersion
    var playlists: [ProfilePlaylistDTO]
    var modules: [ProfileModulePreferenceDTO]
    var updatedAt: Date

    init(
        version: Int = currentVersion,
        playlists: [ProfilePlaylistDTO],
        modules: [ProfileModulePreferenceDTO] = ProfileModulePreferenceDTO.defaults,
        updatedAt: Date
    ) {
        self.version = version
        self.playlists = playlists
        self.modules = Self.normalizedModules(modules)
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case playlists
        case modules
        case updatedAt
    }

    /// Version 1 documents only contained playlists. Decode them with the public
    /// profile's former all-visible order, so existing accounts migrate without
    /// a database rollout or a destructive rewrite.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        playlists = try container.decodeIfPresent(
            [ProfilePlaylistDTO].self,
            forKey: .playlists
        ) ?? []
        modules = Self.normalizedModules(
            try container.decodeIfPresent(
                [ProfileModulePreferenceDTO].self,
                forKey: .modules
            ) ?? ProfileModulePreferenceDTO.defaults
        )
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? .distantPast
    }

    static func normalizedModules(
        _ preferences: [ProfileModulePreferenceDTO]
    ) -> [ProfileModulePreferenceDTO] {
        var seen = Set<ProfileModuleID>()
        var result = preferences.filter { seen.insert($0.module).inserted }
        for preference in ProfileModulePreferenceDTO.defaults
            where seen.insert(preference.module).inserted {
            result.append(preference)
        }
        return result
    }
}

/// Reorderable, owner-controlled sections below a public profile's identity card.
enum ProfileModuleID: String, Codable, Sendable, CaseIterable, Identifiable {
    case compatibility
    case featuredPlaylists
    case listeningStats
    case topTracks
    case sharedMixtapes
    case musicLinks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compatibility: "Music compatibility"
        case .featuredPlaylists: "Featured playlists"
        case .listeningStats: "Listening stats"
        case .topTracks: "In heavy rotation"
        case .sharedMixtapes: "Shared mixtapes"
        case .musicLinks: "Music links"
        }
    }

    var subtitle: String {
        switch self {
        case .compatibility: "Overlap from recent Heartable listening"
        case .featuredPlaylists: "Playlists you choose"
        case .listeningStats: "Recent listening activity"
        case .topTracks: "Songs you play most"
        case .sharedMixtapes: "Mixtapes shared with each friend"
        case .musicLinks: "Connected public music profiles"
        }
    }

    var systemImage: String {
        switch self {
        case .compatibility: "heart.text.square.fill"
        case .featuredPlaylists: "music.note.list"
        case .listeningStats: "chart.bar.fill"
        case .topTracks: "repeat"
        case .sharedMixtapes: "rectangle.stack.badge.play"
        case .musicLinks: "link"
        }
    }
}

struct ProfileModulePreferenceDTO: Codable, Sendable, Equatable, Identifiable {
    var module: ProfileModuleID
    var isVisible: Bool

    var id: ProfileModuleID { module }

    static let defaults = ProfileModuleID.allCases.map {
        ProfileModulePreferenceDTO(module: $0, isVisible: true)
    }
}

struct ProfilePlaylistDTO: Codable, Sendable, Equatable, Identifiable {
    var key: String
    var providerId: ProviderID
    var playlistId: String
    var name: String
    var description: String?
    var imageUrl: String?
    var trackCount: Int
    var owner: String?
    var createdAt: Date?
    var contentRevision: String?

    var id: String { key }

    init(_ playlist: UnifiedPlaylist) {
        key = playlist.key
        providerId = playlist.providerID
        playlistId = playlist.playlistID
        name = playlist.name
        description = playlist.description
        imageUrl = playlist.image?.absoluteString
        trackCount = playlist.trackCount
        owner = playlist.owner
        createdAt = playlist.createdAt
        contentRevision = playlist.contentRevision
    }

    var unified: UnifiedPlaylist {
        UnifiedPlaylist(
            key: key,
            providerID: providerId,
            playlistID: playlistId,
            name: name,
            description: description,
            image: imageUrl.flatMap(URL.init(string:)),
            trackCount: trackCount,
            owner: owner,
            createdAt: createdAt,
            contentRevision: contentRevision
        )
    }
}

// MARK: - Shared value types

/// A region of a track to skip during playback. Stored as jsonb `[{start,end}]`.
struct SkipRegion: Codable, Sendable, Equatable {
    var start: Int
    var end: Int
}

// MARK: - Profiles / discoverability

/// Row returned by the `find_profile(p_query)` RPC. The migration's function
/// returns exactly these four columns (handle/share_code lookup), so the RN
/// `matched_provider`/`matched_handle` fields are not modeled here.
struct FoundProfileDTO: Codable, Sendable, Identifiable {
    let userId: UUID
    var displayName: String?
    var spotifyId: String?
    var avatarUrl: String?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case spotifyId = "spotify_id"
        case avatarUrl = "avatar_url"
    }
}

/// Insert/update payload for `profiles` (partial profile editor + spotify upsert).
/// Optional fields are omitted from the encoded body when nil so we don't clobber
/// existing columns on upsert.
struct ProfileUpsertDTO: Codable, Sendable {
    var userId: UUID
    var spotifyId: String?
    var displayName: String?
    var avatarUrl: String?
    var handle: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case spotifyId = "spotify_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case handle
        case updatedAt = "updated_at"
    }
}

/// Row for `profile_links` (one connected-service handle per provider per user).
struct ProfileLinkDTO: Codable, Sendable {
    var userId: UUID
    var providerId: String
    var handle: String
    var displayName: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case providerId = "provider_id"
        case handle
        case displayName = "display_name"
        case updatedAt = "updated_at"
    }
}

// MARK: - Friends

/// Row in `friendships`. status is one of pending/accepted/declined/blocked.
struct FriendshipDTO: Codable, Sendable, Identifiable {
    let id: UUID
    var requesterId: UUID
    var addresseeId: UUID
    var status: String
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case status
        case createdAt = "created_at"
    }
}

/// The signed-in viewer's relationship to one other Heartable account.
/// Keeping this typed prevents a failed/empty lookup from being confused with
/// an outgoing request and lets every social surface render the same state.
enum FriendRelationship: Sendable, Equatable {
    case none
    case outgoing(UUID)
    case incoming(UUID)
    case friends(UUID)
    case blocked

    static func resolve(
        rows: [FriendshipDTO],
        viewerID: UUID,
        otherID: UUID
    ) -> FriendRelationship {
        let pair = rows.filter {
            ($0.requesterId == viewerID && $0.addresseeId == otherID)
                || ($0.requesterId == otherID && $0.addresseeId == viewerID)
        }

        // Accepted wins defensively if legacy directional duplicates exist.
        if let row = pair.first(where: { $0.status == "accepted" }) {
            return .friends(row.id)
        }
        if pair.contains(where: { $0.status == "blocked" }) {
            return .blocked
        }
        if let row = pair.first(where: {
            $0.status == "pending" && $0.addresseeId == viewerID
        }) {
            return .incoming(row.id)
        }
        if let row = pair.first(where: {
            $0.status == "pending" && $0.requesterId == viewerID
        }) {
            return .outgoing(row.id)
        }
        return .none
    }
}

/// Result of attempting to send a request. Existing relationship states are
/// surfaced instead of being overwritten.
enum FriendRequestOutcome: Sendable, Equatable {
    case sent
    case alreadyFriends(UUID)
    case outgoingPending(UUID)
    case incomingPending(UUID)
    case blocked
}

/// Insert payload for sending a friend request.
struct FriendRequestInsertDTO: Codable, Sendable {
    var requesterId: UUID
    var addresseeId: UUID
    var status: String

    enum CodingKeys: String, CodingKey {
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case status
    }
}

/// Update payload for responding to a friend request.
struct FriendStatusUpdateDTO: Codable, Sendable {
    var status: String
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

/// A friendship plus the hydrated profile of the *other* party. Built in code,
/// not decoded directly from a single query.
struct FriendDTO: Sendable, Identifiable {
    let id: UUID
    var status: String
    var requesterId: UUID
    var addresseeId: UUID
    var profile: ProfileDTO?

    func otherUserID(viewerID: UUID) -> UUID? {
        if requesterId == viewerID { return addresseeId }
        if addresseeId == viewerID { return requesterId }
        return nil
    }
}

// MARK: - Now playing & social

/// Upsert payload for `now_playing` (one row per user).
struct NowPlayingUpsertDTO: Codable, Sendable {
    var userId: UUID
    var trackName: String?
    var artist: String?
    var album: String?
    var albumArt: String?
    var trackUri: String?
    var isPlaying: Bool
    var progressMs: Int?
    var durationMs: Int?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case trackName = "track_name"
        case artist
        case album
        case albumArt = "album_art"
        case trackUri = "track_uri"
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case durationMs = "duration_ms"
        case updatedAt = "updated_at"
    }
}

/// Row read from `now_playing`.
struct NowPlayingRowDTO: Codable, Sendable {
    var userId: UUID
    var trackName: String?
    var artist: String?
    var album: String?
    var albumArt: String?
    var trackUri: String?
    var isPlaying: Bool?
    var progressMs: Int?
    var durationMs: Int?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case trackName = "track_name"
        case artist
        case album
        case albumArt = "album_art"
        case trackUri = "track_uri"
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case durationMs = "duration_ms"
        case updatedAt = "updated_at"
    }
}

/// A friend's now-playing snapshot joined with their profile. Built in code.
struct FriendNowPlayingDTO: Sendable, Identifiable {
    let userId: UUID
    var displayName: String?
    var avatarUrl: String?
    var trackName: String?
    var artist: String?
    var albumArt: String?
    var isPlaying: Bool
    var updatedAt: String

    var id: UUID { userId }
}

/// Defines when a now-playing row is safe to present as live. A TTL prevents a
/// process kill or lost final update from leaving someone "playing" forever.
enum FriendActivityPolicy {
    static let liveTTL: TimeInterval = 90

    static func isLive(
        isPlaying: Bool?,
        trackName: String?,
        updatedAt: String?,
        now: Date = Date()
    ) -> Bool {
        guard isPlaying == true,
              let trackName,
              !trackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let updatedAt,
              let date = parse(updatedAt) else {
            return false
        }
        let age = now.timeIntervalSince(date)
        return age >= -5 && age <= liveTTL
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

/// Insert payload for `play_log`.
struct PlayLogInsertDTO: Codable, Sendable {
    var userId: UUID
    var trackUri: String?
    var trackName: String?
    var artist: String?
    var durationMs: Int
    var albumArt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case trackUri = "track_uri"
        case trackName = "track_name"
        case artist
        case durationMs = "duration_ms"
        case albumArt = "album_art"
    }
}

// MARK: - Play history & leaderboards

/// A `play_log` history row.
struct PlayEntryDTO: Codable, Sendable, Identifiable {
    let id: UUID
    var trackUri: String?
    var trackName: String?
    var artist: String?
    var durationMs: Int?
    var playedAt: String?
    var albumArt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case trackUri = "track_uri"
        case trackName = "track_name"
        case artist
        case durationMs = "duration_ms"
        case playedAt = "played_at"
        case albumArt = "album_art"
    }
}

// MARK: - Friend activity

/// The intentionally small reaction vocabulary accepted by the database.
/// One account may have at most one reaction on a play and may tap the selected
/// reaction again to remove it.
enum FriendActivityReaction: String, Codable, CaseIterable, Sendable {
    case heart
    case fire
    case headphones
    case onRepeat = "on_repeat"

    var systemImage: String {
        switch self {
        case .heart: "heart.fill"
        case .fire: "flame.fill"
        case .headphones: "headphones"
        case .onRepeat: "repeat"
        }
    }

    var accessibilityName: String {
        switch self {
        case .heart: "Heart"
        case .fire: "Fire"
        case .headphones: "Headphones"
        case .onRepeat: "On repeat"
        }
    }
}

/// Stable keyset cursor for the friend-activity RPC. Ordering by both values
/// prevents two plays with the same timestamp from being skipped or duplicated.
struct FriendActivityCursor: Codable, Sendable, Equatable {
    let playedAt: String
    let activityID: UUID
}

/// One accepted friend's qualified `play_log` event, enriched by the RPC with
/// profile identity and reaction state. The play itself remains the durable
/// ledger row; this type does not model a second activity table.
struct FriendActivityEntryDTO: Codable, Sendable, Identifiable, Equatable {
    let activityId: UUID
    let userId: UUID
    var displayName: String?
    var handle: String?
    var avatarUrl: String?
    var trackUri: String?
    var trackName: String
    var artist: String?
    var durationMs: Int?
    var albumArt: String?
    var playedAt: String
    var reactionCounts: [String: Int]
    var viewerReaction: FriendActivityReaction?

    var id: UUID { activityId }
    var cursor: FriendActivityCursor {
        FriendActivityCursor(playedAt: playedAt, activityID: activityId)
    }

    func reactionCount(_ reaction: FriendActivityReaction) -> Int {
        reactionCounts[reaction.rawValue] ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case userId = "user_id"
        case displayName = "display_name"
        case handle
        case avatarUrl = "avatar_url"
        case trackUri = "track_uri"
        case trackName = "track_name"
        case artist
        case durationMs = "duration_ms"
        case albumArt = "album_art"
        case playedAt = "played_at"
        case reactionCounts = "reaction_counts"
        case viewerReaction = "viewer_reaction"
    }

    init(
        activityId: UUID,
        userId: UUID,
        displayName: String? = nil,
        handle: String? = nil,
        avatarUrl: String? = nil,
        trackUri: String? = nil,
        trackName: String,
        artist: String? = nil,
        durationMs: Int? = nil,
        albumArt: String? = nil,
        playedAt: String,
        reactionCounts: [String: Int] = [:],
        viewerReaction: FriendActivityReaction? = nil
    ) {
        self.activityId = activityId
        self.userId = userId
        self.displayName = displayName
        self.handle = handle
        self.avatarUrl = avatarUrl
        self.trackUri = trackUri
        self.trackName = trackName
        self.artist = artist
        self.durationMs = durationMs
        self.albumArt = albumArt
        self.playedAt = playedAt
        self.reactionCounts = reactionCounts
        self.viewerReaction = viewerReaction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityId = try container.decode(UUID.self, forKey: .activityId)
        userId = try container.decode(UUID.self, forKey: .userId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        handle = try container.decodeIfPresent(String.self, forKey: .handle)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        trackUri = try container.decodeIfPresent(String.self, forKey: .trackUri)
        trackName = try container.decode(String.self, forKey: .trackName)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        albumArt = try container.decodeIfPresent(String.self, forKey: .albumArt)
        playedAt = try container.decode(String.self, forKey: .playedAt)
        reactionCounts =
            (try? container.decode([String: Int].self, forKey: .reactionCounts)) ?? [:]
        viewerReaction =
            try? container.decodeIfPresent(
                FriendActivityReaction.self,
                forKey: .viewerReaction
            )
    }
}

/// Upsert payload for `friend_activity_reactions`.
struct FriendActivityReactionUpsertDTO: Codable, Sendable {
    let activityId: UUID
    let userId: UUID
    let reaction: FriendActivityReaction

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case userId = "user_id"
        case reaction
    }
}

/// A contributor to a song-leaderboard entry. The RPC nests these as camelCase
/// JSON (userId/displayName/avatarUrl), matching the RN reader.
struct SongLeaderboardContributorDTO: Codable, Sendable {
    var userId: String?
    var displayName: String?
    var avatarUrl: String?
}

/// A row from the `song_leaderboard(window_days)` RPC.
struct SongLeaderboardEntryDTO: Codable, Sendable, Identifiable {
    var trackUri: String
    var trackName: String?
    var artist: String?
    var plays: Int
    var contributors: [SongLeaderboardContributorDTO]

    var id: String { trackUri }

    enum CodingKeys: String, CodingKey {
        case trackUri = "track_uri"
        case trackName = "track_name"
        case artist
        case plays
        case contributors
    }

    init(
        trackUri: String,
        trackName: String?,
        artist: String?,
        plays: Int,
        contributors: [SongLeaderboardContributorDTO]
    ) {
        self.trackUri = trackUri
        self.trackName = trackName
        self.artist = artist
        self.plays = plays
        self.contributors = contributors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackUri = try c.decode(String.self, forKey: .trackUri)
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        // `plays` may arrive as a number or numeric string from the RPC.
        if let i = try? c.decode(Int.self, forKey: .plays) {
            plays = i
        } else if let s = try? c.decode(String.self, forKey: .plays), let i = Int(s) {
            plays = i
        } else if let d = try? c.decode(Double.self, forKey: .plays) {
            plays = Int(d)
        } else {
            plays = 0
        }
        contributors = (try? c.decode([SongLeaderboardContributorDTO].self, forKey: .contributors)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trackUri, forKey: .trackUri)
        try c.encodeIfPresent(trackName, forKey: .trackName)
        try c.encodeIfPresent(artist, forKey: .artist)
        try c.encode(plays, forKey: .plays)
        try c.encode(contributors, forKey: .contributors)
    }
}

/// Transparent overlap derived only from observed, qualified Heartable plays.
/// The score is the Sørensen-Dice coefficient across both listeners' track sets;
/// it never claims access to provider-private lifetime play counts.
struct FriendCompatibilitySummary: Sendable, Equatable {
    struct SharedTrack: Sendable, Equatable, Identifiable {
        var identity: String
        var trackName: String
        var artist: String?
        var combinedPlays: Int

        var id: String { identity }
    }

    var score: Int
    var sharedTrackCount: Int
    var viewerTrackCount: Int
    var friendTrackCount: Int
    var sharedTracks: [SharedTrack]

    static func build(
        entries: [SongLeaderboardEntryDTO],
        viewerID: UUID,
        friendID: UUID
    ) -> FriendCompatibilitySummary? {
        let viewer = viewerID.uuidString.lowercased()
        let friend = friendID.uuidString.lowercased()
        var viewerTracks = Set<String>()
        var friendTracks = Set<String>()
        var entryByIdentity: [String: SongLeaderboardEntryDTO] = [:]

        for entry in entries {
            let identity = canonicalIdentity(entry)
            let contributors = Set(
                entry.contributors.compactMap { $0.userId?.lowercased() }
            )
            if contributors.contains(viewer) { viewerTracks.insert(identity) }
            if contributors.contains(friend) { friendTracks.insert(identity) }
            if let existing = entryByIdentity[identity] {
                if entry.plays > existing.plays {
                    entryByIdentity[identity] = entry
                }
            } else {
                entryByIdentity[identity] = entry
            }
        }

        guard !viewerTracks.isEmpty, !friendTracks.isEmpty else { return nil }
        let overlap = viewerTracks.intersection(friendTracks)
        let denominator = viewerTracks.count + friendTracks.count
        let score = denominator == 0
            ? 0
            : Int((Double(2 * overlap.count) / Double(denominator) * 100).rounded())
        let shared = overlap.compactMap { identity -> SharedTrack? in
            guard let entry = entryByIdentity[identity] else { return nil }
            return SharedTrack(
                identity: identity,
                trackName: entry.trackName ?? "Unknown track",
                artist: entry.artist,
                combinedPlays: entry.plays
            )
        }
        .sorted {
            if $0.combinedPlays != $1.combinedPlays {
                return $0.combinedPlays > $1.combinedPlays
            }
            return $0.trackName.localizedCaseInsensitiveCompare($1.trackName)
                == .orderedAscending
        }

        return FriendCompatibilitySummary(
            score: score,
            sharedTrackCount: overlap.count,
            viewerTrackCount: viewerTracks.count,
            friendTrackCount: friendTracks.count,
            sharedTracks: Array(shared.prefix(3))
        )
    }

    private static func canonicalIdentity(_ entry: SongLeaderboardEntryDTO) -> String {
        let title = normalized(entry.trackName)
        let artist = normalized(entry.artist)
        if !title.isEmpty { return "\(title)|\(artist)" }
        return entry.trackUri.lowercased()
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// A row from the `friend_leaderboard(window_days)` RPC.
struct LeaderboardEntryDTO: Codable, Sendable, Identifiable {
    var userId: UUID
    var displayName: String?
    var avatarUrl: String?
    var tracks: Int
    var minutes: Int
    var isMe: Bool

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case tracks
        case minutes
        case isMe = "is_me"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        tracks = (try? c.decode(Int.self, forKey: .tracks)) ?? Int((try? c.decode(Double.self, forKey: .tracks)) ?? 0)
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? Int((try? c.decode(Double.self, forKey: .minutes)) ?? 0)
        isMe = (try? c.decode(Bool.self, forKey: .isMe)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try c.encode(tracks, forKey: .tracks)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(isMe, forKey: .isMe)
    }
}

// MARK: - Track weights

/// Row in `track_weights` (per-user per-track shuffle weight).
struct TrackWeightDTO: Codable, Sendable {
    var trackUri: String
    var weight: Double

    enum CodingKeys: String, CodingKey {
        case trackUri = "track_uri"
        case weight
    }
}

/// Upsert payload for `track_weights`.
struct TrackWeightUpsertDTO: Codable, Sendable {
    var userId: UUID
    var trackUri: String
    var weight: Double

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case trackUri = "track_uri"
        case weight
    }
}

// MARK: - Skip versions

/// Row in `track_skip_versions`.
struct TrackSkipVersionDTO: Codable, Sendable, Identifiable {
    let id: UUID
    var owner: UUID?
    var spotifyTrackUri: String
    var label: String
    var skipRegions: [SkipRegion]
    var fadeInMs: Int?
    var fadeOutMs: Int?
    var isActive: Bool
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case owner
        case spotifyTrackUri = "spotify_track_uri"
        case label
        case skipRegions = "skip_regions"
        case fadeInMs = "fade_in_ms"
        case fadeOutMs = "fade_out_ms"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        owner = try c.decodeIfPresent(UUID.self, forKey: .owner)
        spotifyTrackUri = try c.decode(String.self, forKey: .spotifyTrackUri)
        label = (try? c.decode(String.self, forKey: .label)) ?? "Version"
        skipRegions = (try? c.decode([SkipRegion].self, forKey: .skipRegions)) ?? []
        fadeInMs = try c.decodeIfPresent(Int.self, forKey: .fadeInMs)
        fadeOutMs = try c.decodeIfPresent(Int.self, forKey: .fadeOutMs)
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? false
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

/// Insert payload for a new skip version. owner defaults to auth.uid() server-side.
struct SkipVersionInsertDTO: Codable, Sendable {
    var spotifyTrackUri: String
    var label: String
    var skipRegions: [SkipRegion]

    enum CodingKeys: String, CodingKey {
        case spotifyTrackUri = "spotify_track_uri"
        case label
        case skipRegions = "skip_regions"
    }
}

/// Partial update payload for a skip version (label and/or regions).
struct SkipVersionUpdateDTO: Codable, Sendable {
    var label: String?
    var skipRegions: [SkipRegion]?

    enum CodingKeys: String, CodingKey {
        case label
        case skipRegions = "skip_regions"
    }
}

/// Update payload for toggling a skip version's active flag.
struct SkipVersionActiveDTO: Codable, Sendable {
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
    }
}

// MARK: - Playlist folders

/// Row read from `playlist_folders` joined with a count of its items.
struct FolderDTO: Sendable, Identifiable {
    let id: UUID
    var name: String
    var itemCount: Int
}

/// Insert payload for a new folder.
struct FolderInsertDTO: Codable, Sendable {
    var owner: UUID
    var name: String

    enum CodingKeys: String, CodingKey {
        case owner
        case name
    }
}

/// Update payload for renaming a folder.
struct FolderRenameDTO: Codable, Sendable {
    var name: String
}

/// Row in `playlist_folder_items`.
struct FolderItemDTO: Codable, Sendable, Identifiable {
    var playlistKey: String
    var providerId: String
    var playlistId: String
    var name: String
    var image: String?
    var ownerName: String?
    var trackCount: Int?

    var id: String { playlistKey }

    enum CodingKeys: String, CodingKey {
        case playlistKey = "playlist_key"
        case providerId = "provider_id"
        case playlistId = "playlist_id"
        case name
        case image
        case ownerName = "owner_name"
        case trackCount = "track_count"
    }
}

/// Upsert payload for adding a playlist to a folder.
struct FolderItemInsertDTO: Codable, Sendable {
    var folderId: UUID
    var playlistKey: String
    var providerId: String
    var playlistId: String
    var name: String
    var image: String?
    var ownerName: String?
    var trackCount: Int

    enum CodingKeys: String, CodingKey {
        case folderId = "folder_id"
        case playlistKey = "playlist_key"
        case providerId = "provider_id"
        case playlistId = "playlist_id"
        case name
        case image
        case ownerName = "owner_name"
        case trackCount = "track_count"
    }
}

/// Helpers to decode the folder list with embedded item count.
struct FolderCountRow: Codable, Sendable {
    var count: Int
}
struct FolderRowDTO: Codable, Sendable {
    let id: UUID
    var name: String
    var playlistFolderItems: [FolderCountRow]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case playlistFolderItems = "playlist_folder_items"
    }
}

/// Row used to read just the `folder_id` of items containing a playlist.
struct FolderIdRowDTO: Codable, Sendable {
    var folderId: UUID

    enum CodingKeys: String, CodingKey {
        case folderId = "folder_id"
    }
}

// MARK: - Mixtapes

/// Row read from `mixtapes`, plus a derived `mine` flag set in code.
struct MixtapeDTO: Codable, Sendable, Identifiable {
    let id: UUID
    var owner: UUID
    var title: String?
    var description: String?
    var coverUrl: String?
    var createdAt: String?
    /// Not a column — set by the caller after decoding (owner == me).
    var mine: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case owner
        case title
        case description
        case coverUrl = "cover_url"
        case createdAt = "created_at"
    }
}

/// Row in `mixtape_tracks`.
struct MixtapeTrackDTO: Codable, Sendable, Identifiable {
    let id: UUID
    var mixtapeId: UUID?
    var position: Int?
    var trackUri: String
    var trackName: String?
    var artist: String?
    var albumArt: String?
    var durationMs: Int?
    var skipRegions: [SkipRegion]
    var note: String?
    var noteImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mixtapeId = "mixtape_id"
        case position
        case trackUri = "track_uri"
        case trackName = "track_name"
        case artist
        case albumArt = "album_art"
        case durationMs = "duration_ms"
        case skipRegions = "skip_regions"
        case note
        case noteImageUrl = "note_image_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        mixtapeId = try c.decodeIfPresent(UUID.self, forKey: .mixtapeId)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        trackUri = try c.decode(String.self, forKey: .trackUri)
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        albumArt = try c.decodeIfPresent(String.self, forKey: .albumArt)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        skipRegions = (try? c.decode([SkipRegion].self, forKey: .skipRegions)) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
        noteImageUrl = try c.decodeIfPresent(String.self, forKey: .noteImageUrl)
    }
}

/// Bundle returned by `getMixtape`.
struct MixtapeDetailDTO: Sendable {
    var mixtape: MixtapeDTO
    var tracks: [MixtapeTrackDTO]
}

/// Result of `listMixtapes`.
struct MixtapeListDTO: Sendable {
    var mine: [MixtapeDTO]
    var shared: [MixtapeDTO]
}

/// Insert payload for a new mixtape.
struct MixtapeInsertDTO: Codable, Sendable {
    var title: String
    var owner: UUID
}

/// Partial update payload for a mixtape.
struct MixtapeUpdateDTO: Codable, Sendable {
    var title: String?
    var description: String?
    var coverUrl: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case coverUrl = "cover_url"
        case updatedAt = "updated_at"
    }
}

/// Insert payload for a new mixtape track.
struct MixtapeTrackInsertDTO: Codable, Sendable {
    var mixtapeId: UUID
    var position: Int
    var trackUri: String
    var trackName: String?
    var artist: String?
    var albumArt: String?
    var durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case mixtapeId = "mixtape_id"
        case position
        case trackUri = "track_uri"
        case trackName = "track_name"
        case artist
        case albumArt = "album_art"
        case durationMs = "duration_ms"
    }
}

/// Partial update payload for a mixtape track.
struct MixtapeTrackUpdateDTO: Codable, Sendable {
    var skipRegions: [SkipRegion]?
    var note: String?
    var noteImageUrl: String?
    var position: Int?

    enum CodingKeys: String, CodingKey {
        case skipRegions = "skip_regions"
        case note
        case noteImageUrl = "note_image_url"
        case position
    }
}

/// Upsert payload for a mixtape share.
struct MixtapeShareDTO: Codable, Sendable {
    var mixtapeId: UUID
    var sharedWith: UUID

    enum CodingKeys: String, CodingKey {
        case mixtapeId = "mixtape_id"
        case sharedWith = "shared_with"
    }
}

/// Row used to read just the `shared_with` of a mixtape's shares.
struct MixtapeShareRowDTO: Codable, Sendable {
    var sharedWith: UUID

    enum CodingKeys: String, CodingKey {
        case sharedWith = "shared_with"
    }
}

// MARK: - Snapshots / backups

/// Row in `library_snapshots`.
struct LibrarySnapshotDTO: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String?
    var playlistCount: Int?
    var trackCount: Int?
    var likedCount: Int?
    var createdAt: String?
    var providers: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case playlistCount = "playlist_count"
        case trackCount = "track_count"
        case likedCount = "liked_count"
        case createdAt = "created_at"
        case providers
    }
}

/// Row in `snapshot_playlists`.
struct SnapshotPlaylistDTO: Codable, Sendable, Identifiable {
    let id: UUID
    var spotifyPlaylistId: String?
    var name: String?
    var description: String?
    var imageUrl: String?
    var ownerName: String?
    var trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case spotifyPlaylistId = "spotify_playlist_id"
        case name
        case description
        case imageUrl = "image_url"
        case ownerName = "owner_name"
        case trackCount = "track_count"
    }
}

/// Row in `snapshot_tracks`.
struct SnapshotTrackDTO: Codable, Sendable {
    var spotifyTrackUri: String
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var albumArtUrl: String?
    var durationMs: Int?
    var position: Int?

    enum CodingKeys: String, CodingKey {
        case spotifyTrackUri = "spotify_track_uri"
        case trackName = "track_name"
        case artistName = "artist_name"
        case albumName = "album_name"
        case albumArtUrl = "album_art_url"
        case durationMs = "duration_ms"
        case position
    }
}

/// Row in `snapshot_liked_tracks`.
struct SnapshotLikedTrackDTO: Codable, Sendable {
    var spotifyTrackUri: String
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var albumArtUrl: String?
    var durationMs: Int?
    var addedAt: String?
    var position: Int?

    enum CodingKeys: String, CodingKey {
        case spotifyTrackUri = "spotify_track_uri"
        case trackName = "track_name"
        case artistName = "artist_name"
        case albumName = "album_name"
        case albumArtUrl = "album_art_url"
        case durationMs = "duration_ms"
        case addedAt = "added_at"
        case position
    }
}

/// Result of the `snapshot-library` edge function.
struct CreateSnapshotResultDTO: Codable, Sendable {
    var snapshotId: String
    var playlistCount: Int
    var trackCount: Int
    var likedCount: Int?
}

/// Result of the `restore-snapshot` edge function. `total` is the count the
/// function reports as restored (it equals `restored.count`); `errors` lists any
/// playlists that failed to recreate, present only on partial failure.
struct RestoreSnapshotResultDTO: Codable, Sendable {
    var restored: [String]
    var total: Int
    var errors: [String]?
}

/// Structured error body returned by the edge functions on failure
/// (`{ "error": "..." }`). Decoded out of `FunctionsError.httpError`.
struct EdgeErrorDTO: Codable, Sendable {
    var error: String?
}

/// Row used to read just the `id` of snapshot child tables during cascading delete.
struct IdRowDTO: Codable, Sendable {
    let id: UUID
}
