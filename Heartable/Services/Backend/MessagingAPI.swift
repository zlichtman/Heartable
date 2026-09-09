import Foundation
import Supabase

// MARK: - Message kinds & payloads

/// The kind of a message. Maps to the `kind` text column on `public.messages`
/// (CHECK in ('text','song','playlist','mixtape')).
enum MessageKind: String, Codable, Sendable {
    case text
    case song
    case playlist
    case mixtape
}

enum MessagingError: LocalizedError {
    case invalidMessage
    case missingInsertedMessage

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            return "This message could not be sent."
        case .missingInsertedMessage:
            return "The server did not confirm the message."
        }
    }
}

/// The structured `payload` jsonb for a non-text message. Exactly one case is
/// populated per message, matching its `kind`. Decoded leniently so an unknown
/// shape never crashes the thread.
struct MessagePayload: Codable, Sendable, Equatable {
    /// kind == .song
    var song: Song?
    /// kind == .playlist
    var playlist: Playlist?
    /// kind == .mixtape
    var mixtape: Mixtape?

    struct Song: Codable, Sendable, Equatable {
        var uri: String
        var name: String?
        var artist: String?
        var art: String?
        /// Explicit playback identity for new messages. Older messages omit
        /// these fields and remain playable through URI inference.
        var providerID: String? = nil
        var providerTrackID: String? = nil
        var durationMs: Int? = nil

        enum CodingKeys: String, CodingKey {
            case uri, name, artist, art
            case providerID = "provider_id"
            case providerTrackID = "provider_track_id"
            case durationMs = "duration_ms"
        }
    }

    struct Playlist: Codable, Sendable, Equatable {
        var providerID: String?
        var id: String?
        var name: String?
        var image: String?

        enum CodingKeys: String, CodingKey {
            case providerID = "provider_id"
            case id, name, image
        }
    }

    struct Mixtape: Codable, Sendable, Equatable {
        var id: String?
        var name: String?
    }

    init(song: Song? = nil, playlist: Playlist? = nil, mixtape: Mixtape? = nil) {
        self.song = song
        self.playlist = playlist
        self.mixtape = mixtape
    }
}

// MARK: - Message row

/// A decoded row from `public.messages`.
struct MessageDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var senderId: UUID
    var recipientId: UUID
    var body: String?
    var kind: MessageKind
    var payload: MessagePayload?
    var createdAt: String
    var readAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case body
        case kind
        case payload
        case createdAt = "created_at"
        case readAt = "read_at"
    }

    /// Tolerate an unrecognised `kind` (future server values) by falling back to
    /// .text rather than failing the whole decode of a page of messages.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        senderId = try c.decode(UUID.self, forKey: .senderId)
        recipientId = try c.decode(UUID.self, forKey: .recipientId)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        kind = (try? c.decode(MessageKind.self, forKey: .kind)) ?? .text
        payload = try? c.decodeIfPresent(MessagePayload.self, forKey: .payload)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
    }
}

/// Insert payload for sending a message. `id`/`created_at` use column defaults.
private struct MessageInsertDTO: Codable, Sendable {
    var senderId: UUID
    var recipientId: UUID
    var body: String?
    var kind: String
    var payload: MessagePayload?

    enum CodingKeys: String, CodingKey {
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case body
        case kind
        case payload
    }
}

/// One conversation: a friend plus the most recent message and unread count.
/// Built in code from the friend list + recent messages, never decoded directly.
struct ConversationDTO: Sendable, Identifiable {
    let friend: ProfileDTO
    var lastMessage: MessageDTO?
    var unreadCount: Int

    var id: UUID { friend.userId }
}

// MARK: - Messaging API

extension BackendAPI {
    /// The shared client + current uid, re-derived here so this extension stays
    /// self-contained (BackendAPI's own `client`/`myUID` are private).
    private var msgClient: SupabaseClient { SupabaseClientProvider.shared }
    private func msgUID() async -> UUID? { try? await msgClient.auth.session.user.id }

    /// The signed-in user's id (used by ChatStore to side message bubbles).
    func currentUserID() async -> UUID? { await msgUID() }

    /// All accepted friends as conversations, each hydrated with its exact latest
    /// message and unread count. We intentionally query each friend independently:
    /// a single busy conversation can no longer evict quieter friends from a
    /// global recent-message window.
    func fetchConversations() async throws -> [ConversationDTO] {
        guard let uid = await msgUID() else { throw BackendError.notSignedIn }
        let friends = try await fetchFriends().compactMap { $0.profile }
        guard !friends.isEmpty else { return [] }

        let convos = try await withThrowingTaskGroup(
            of: ConversationDTO.self,
            returning: [ConversationDTO].self
        ) { group in
            for friend in friends {
                group.addTask {
                    try await conversationSnapshot(friend: friend, myID: uid)
                }
            }
            var rows: [ConversationDTO] = []
            for try await row in group { rows.append(row) }
            return rows
        }

        return convos.sorted { a, b in
            switch (a.lastMessage?.createdAt, b.lastMessage?.createdAt) {
            case let (la?, lb?): return la > lb
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                let na = a.friend.displayName ?? a.friend.handle ?? ""
                let nb = b.friend.displayName ?? b.friend.handle ?? ""
                return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending
            }
        }
    }

    private func conversationSnapshot(
        friend: ProfileDTO,
        myID uid: UUID
    ) async throws -> ConversationDTO {
        let a = uid.uuidString
        let b = friend.userId.uuidString
        async let latestTask: [MessageDTO] = msgClient
            .from("messages")
            .select()
            .or("and(sender_id.eq.\(a),recipient_id.eq.\(b)),and(sender_id.eq.\(b),recipient_id.eq.\(a))")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        async let unreadTask = msgClient
            .from("messages")
            .select("id", head: true, count: .exact)
            .eq("recipient_id", value: a)
            .eq("sender_id", value: b)
            .is("read_at", value: nil)
            .execute()

        let (latest, unreadResponse) = try await (latestTask, unreadTask)
        return ConversationDTO(
            friend: friend,
            lastMessage: latest.first,
            unreadCount: unreadResponse.count ?? 0
        )
    }

    /// The newest thread page with one friend, returned oldest-first for display.
    /// Sorting descending before the limit ensures a long conversation never
    /// strands the user on its oldest 1,000 messages.
    func fetchMessages(with friendID: UUID) async throws -> [MessageDTO] {
        guard let uid = await msgUID() else { throw BackendError.notSignedIn }
        let a = uid.uuidString
        let b = friendID.uuidString
        let rows: [MessageDTO] = try await msgClient
            .from("messages")
            .select()
            .or("and(sender_id.eq.\(a),recipient_id.eq.\(b)),and(sender_id.eq.\(b),recipient_id.eq.\(a))")
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
            .value
        return Array(rows.reversed())
    }

    /// Send a message to a friend. RLS enforces sender == me AND accepted-friend.
    /// Returns the inserted row so the UI can append it immediately.
    @discardableResult
    func sendMessage(to recipientID: UUID,
                     body: String?,
                     kind: MessageKind = .text,
                     payload: MessagePayload? = nil) async throws -> MessageDTO? {
        guard let uid = await msgUID() else { throw BackendError.notSignedIn }
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = (trimmed?.isEmpty ?? true) ? nil : trimmed
        switch kind {
        case .text:
            guard cleanBody != nil, payload == nil else {
                throw MessagingError.invalidMessage
            }
        case .song:
            guard payload?.song != nil else { throw MessagingError.invalidMessage }
        case .playlist:
            guard payload?.playlist != nil else { throw MessagingError.invalidMessage }
        case .mixtape:
            guard payload?.mixtape != nil else { throw MessagingError.invalidMessage }
        }
        let row = MessageInsertDTO(
            senderId: uid,
            recipientId: recipientID,
            body: cleanBody,
            kind: kind.rawValue,
            payload: payload
        )
        let inserted: [MessageDTO] = try await msgClient
            .from("messages")
            .insert(row)
            .select()
            .execute()
            .value
        return inserted.first
    }

    /// Mark every unread message FROM this friend TO me as read. The caller only
    /// clears local unread state after this request succeeds.
    func markRead(with friendID: UUID) async throws {
        guard let uid = await msgUID() else { throw BackendError.notSignedIn }
        try await msgClient
            .from("messages")
            .update(["read_at": ISO8601DateFormatter().string(from: Date())])
            .eq("recipient_id", value: uid.uuidString)
            .eq("sender_id", value: friendID.uuidString)
            .is("read_at", value: nil)
            .execute()
    }

    /// Unsend (delete) a message I sent. RLS: only the sender may delete.
    func unsendMessage(id: UUID) async throws {
        try await msgClient
            .from("messages")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}
