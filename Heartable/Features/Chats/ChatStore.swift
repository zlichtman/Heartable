import Foundation
import Observation

/// Drives the Chats feature: the conversation list and the currently-open
/// thread. Reads/writes via `BackendAPI` (the `MessagingAPI` extension).
///
/// Realtime vs poll: we POLL the open thread every 3s (plus a refresh on appear
/// and an optimistic append on send), mirroring the existing `NowPlayingSync`
/// poll cadence. This avoids Realtime channel lifecycle + Swift 6 concurrency
/// overhead for a feature where 3s latency is fine. The `messages` table has
/// Realtime enabled if a future pass wants to upgrade this in place.
@MainActor
@Observable
final class ChatStore {
    // Conversation list
    private(set) var conversations: [ConversationDTO] = []
    private(set) var loadingConversations = false
    private(set) var conversationError: String?

    // Open thread
    private(set) var openFriend: ProfileDTO?
    private(set) var messages: [MessageDTO] = []
    private(set) var loadingMessages = false
    private(set) var threadError: String?
    private(set) var sending = false

    /// Total unread across all conversations (for a tab badge if wanted).
    var totalUnread: Int { conversations.reduce(0) { $0 + $1.unreadCount } }

    /// My own user id, resolved lazily for siding bubbles (mine vs theirs).
    private(set) var currentUserID: UUID?

    private let api = BackendAPI.shared
    private var pollTask: Task<Void, Never>?
    private var sceneIsActive = true
    private var lifecycleID = UUID()

    // MARK: - Conversation list

    /// Resolve (and cache) my own user id; awaited by the thread view so bubbles
    /// are sided correctly on first render.
    func resolveCurrentUserID() async -> UUID? {
        if let id = currentUserID { return id }
        let requestID = lifecycleID
        let id = await api.currentUserID()
        guard lifecycleID == requestID else { return nil }
        currentUserID = id
        return id
    }

    func loadConversations() async {
        guard !loadingConversations else { return }
        let requestID = lifecycleID
        loadingConversations = true
        defer {
            if lifecycleID == requestID { loadingConversations = false }
        }
        do {
            let fetched = try await api.fetchConversations()
            guard lifecycleID == requestID else { return }
            conversations = fetched
            conversationError = nil
        } catch {
            guard lifecycleID == requestID else { return }
            // Preserve the last good list. A transient outage must never look like
            // the user suddenly lost every friend and conversation.
            conversationError = Self.message(for: error)
        }
    }

    // MARK: - Open thread

    /// Open a thread with a friend: load history, mark read, start polling.
    func open(_ friend: ProfileDTO) {
        guard openFriend?.userId != friend.userId else { return }
        openFriend = friend
        messages = []
        loadingMessages = true
        threadError = nil
        if sceneIsActive { startPolling(friendID: friend.userId) }
    }

    /// Close the open thread and stop polling.
    func close() {
        pollTask?.cancel()
        pollTask = nil
        openFriend = nil
        messages = []
        loadingMessages = false
        threadError = nil
    }

    /// Suspend network work while the app is backgrounded, then immediately
    /// reconcile the still-open conversation when it becomes active again.
    func setSceneActive(_ active: Bool) {
        guard sceneIsActive != active else { return }
        sceneIsActive = active
        if active, let friendID = openFriend?.userId {
            startPolling(friendID: friendID)
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    /// Refresh the open thread once (used on appear and by the poll loop).
    @discardableResult
    func refreshOpenThread() async -> Bool {
        guard let friend = openFriend else { return false }
        let requestID = lifecycleID
        let previousCount = messages.count
        let previousLastID = messages.last?.id
        do {
            let fetched = try await api.fetchMessages(with: friend.userId)
            // Only replace if still on the same thread (avoids a late response
            // from a previous thread clobbering the current one).
            guard lifecycleID == requestID,
                  openFriend?.userId == friend.userId else { return false }
            messages = fetched
            loadingMessages = false
            threadError = nil
            return fetched.count != previousCount || fetched.last?.id != previousLastID
        } catch {
            guard lifecycleID == requestID,
                  openFriend?.userId == friend.userId else { return false }
            // Keep the last good messages visible while connectivity recovers.
            loadingMessages = false
            threadError = Self.message(for: error)
            return false
        }
    }

    /// Mark a specific thread read. Capturing the friend id prevents a canceled
    /// poll for one conversation from marking a newly-opened conversation.
    func markRead(friendID: UUID) async {
        guard sceneIsActive, openFriend?.userId == friendID else { return }
        let requestID = lifecycleID
        do {
            try await api.markRead(with: friendID)
            guard lifecycleID == requestID,
                  openFriend?.userId == friendID else { return }
            if let idx = conversations.firstIndex(
                where: { $0.friend.userId == friendID }
            ) {
                conversations[idx].unreadCount = 0
            }
        } catch {
            guard lifecycleID == requestID,
                  openFriend?.userId == friendID else { return }
            threadError = Self.message(for: error)
        }
    }

    // MARK: - Sending

    @discardableResult
    func sendText(_ body: String) async -> Bool {
        await send(body: body, kind: .text, payload: nil)
    }

    /// Send the currently-playing track as a 'song' message.
    @discardableResult
    func sendNowPlaying(_ now: PlayerStore.Now) async -> Bool {
        let payload = MessagePayload(song: .init(
            uri: now.uri,
            name: now.name,
            artist: now.artist,
            art: now.artworkURL?.absoluteString,
            providerID: now.source.rawValue,
            providerTrackID: now.providerTrackID,
            durationMs: now.durationMs
        ))
        return await send(body: nil, kind: .song, payload: payload)
    }

    @discardableResult
    func send(
        body: String?,
        kind: MessageKind,
        payload: MessagePayload?
    ) async -> Bool {
        guard let friend = openFriend, !sending else { return false }
        let requestID = lifecycleID
        sending = true
        defer {
            if lifecycleID == requestID { sending = false }
        }
        do {
            guard let inserted = try await api.sendMessage(
                to: friend.userId, body: body, kind: kind, payload: payload
            ) else {
                throw MessagingError.missingInsertedMessage
            }
            guard lifecycleID == requestID else { return false }
            if openFriend?.userId == friend.userId,
               !messages.contains(where: { $0.id == inserted.id }) {
                messages.append(inserted)
            }
            threadError = nil
            upsertConversation(friend: friend, lastMessage: inserted)
            return true
        } catch {
            guard lifecycleID == requestID,
                  openFriend?.userId == friend.userId else { return false }
            threadError = Self.message(for: error)
            return false
        }
    }

    func clearThreadError() {
        threadError = nil
    }

    /// Clear all account-owned state and stop outstanding work before another
    /// signed-in account can mount the app shell.
    func reset() {
        lifecycleID = UUID()
        pollTask?.cancel()
        pollTask = nil
        conversations = []
        loadingConversations = false
        conversationError = nil
        openFriend = nil
        messages = []
        loadingMessages = false
        threadError = nil
        sending = false
        currentUserID = nil
        sceneIsActive = true
    }

    // MARK: - Poll loop

    private func startPolling(friendID: UUID) {
        pollTask?.cancel()
        let requestID = lifecycleID
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshOpenThread()
            guard !Task.isCancelled,
                  self.lifecycleID == requestID,
                  self.sceneIsActive,
                  self.openFriend?.userId == friendID else { return }
            await self.markRead(friendID: friendID)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                guard self.sceneIsActive, self.openFriend?.userId == friendID else { break }
                let changed = await self.refreshOpenThread()
                guard !Task.isCancelled,
                      self.lifecycleID == requestID,
                      self.sceneIsActive,
                      self.openFriend?.userId == friendID else { break }
                if changed { await self.markRead(friendID: friendID) }
            }
        }
    }

    private func upsertConversation(
        friend: ProfileDTO,
        lastMessage: MessageDTO
    ) {
        if let idx = conversations.firstIndex(
            where: { $0.friend.userId == friend.userId }
        ) {
            conversations[idx].lastMessage = lastMessage
            conversations[idx].unreadCount = 0
        } else {
            conversations.append(
                ConversationDTO(
                    friend: friend,
                    lastMessage: lastMessage,
                    unreadCount: 0
                )
            )
        }
        conversations.sort {
            ($0.lastMessage?.createdAt ?? "") > ($1.lastMessage?.createdAt ?? "")
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return message
        }
        return "Could not reach Heartable. Pull to try again."
    }
}
