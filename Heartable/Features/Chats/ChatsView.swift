import SwiftUI

/// Chats tab. Lists every accepted friend as a conversation (so you can start a
/// chat with anyone), showing avatar, name, last-message preview, an unread dot,
/// and a relative timestamp. Tapping opens the thread.
struct ChatsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(ChatStore.self) private var chats
    @State private var selected: SelectedFriend?

    var body: some View {
        NavigationStack {
            content
                .background(theme.palette.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $selected) { sel in
                    ConversationView(friend: sel.profile, chats: chats)
                }
        }
        .task { await chats.loadConversations() }
        .onChange(of: selected) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            Task { await chats.loadConversations() }
        }
    }

    /// A Hashable/Identifiable wrapper so ProfileDTO (Codable only) can drive a
    /// `navigationDestination(item:)`.
    struct SelectedFriend: Identifiable, Hashable {
        let profile: ProfileDTO
        var id: UUID { profile.userId }
        static func == (l: SelectedFriend, r: SelectedFriend) -> Bool { l.id == r.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if chats.conversationError != nil,
                       !chats.conversations.isEmpty {
                        conversationErrorBanner
                    }
                    if chats.conversations.isEmpty {
                        if chats.loadingConversations {
                            loadingState
                        } else if chats.conversationError != nil {
                            errorState
                        } else {
                            emptyState
                        }
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(chats.conversations) { convo in
                                Button {
                                    selected = SelectedFriend(profile: convo.friend)
                                } label: {
                                    ConversationRow(convo: convo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .refreshable { await chats.loadConversations() }
        }
    }

    private var header: some View {
        HeartablePageHeader(tab: .chats)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(theme.palette.rose)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(theme.palette.rose)
            Text("No friends yet")
                .font(Typography.semibold(17))
                .foregroundStyle(theme.palette.text)
            Text("Add friends from Heartable to start sharing songs, playlists, and mixtapes.")
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 38))
                .foregroundStyle(theme.palette.rose)
            Text("Chats couldn’t load")
                .font(Typography.semibold(17))
                .foregroundStyle(theme.palette.text)
            Text(chats.conversationError ?? "Pull to try again.")
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await chats.loadConversations() }
            }
            .font(Typography.semibold(14))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(theme.palette.rose, in: Capsule())
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    private var conversationErrorBanner: some View {
        Button {
            Task { await chats.loadConversations() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(theme.palette.rose)
                Text("Couldn’t refresh chats")
                    .font(Typography.medium(13))
                    .foregroundStyle(theme.palette.text)
                Spacer()
                Text("Retry")
                    .font(Typography.semibold(12))
                    .foregroundStyle(theme.palette.rose)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                theme.palette.card,
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.md,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }
}

/// One row in the conversation list.
private struct ConversationRow: View {
    @Environment(ThemeStore.self) private var theme
    let convo: ConversationDTO

    private var name: String {
        convo.friend.displayName ?? convo.friend.handle ?? "Friend"
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(urlString: convo.friend.avatarUrl, name: name, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(Typography.semibold(16))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let ts = convo.lastMessage?.createdAt {
                        Text(ChatTime.relative(ts))
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                }
                HStack(spacing: 6) {
                    Text(preview)
                        .font(Typography.body(14))
                        .foregroundStyle(convo.unreadCount > 0
                                         ? theme.palette.text
                                         : theme.palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if convo.unreadCount > 0 {
                        Circle()
                            .fill(theme.palette.rose)
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var preview: String {
        guard let m = convo.lastMessage else { return "Say hi" }
        switch m.kind {
        case .text:     return m.body ?? ""
        case .song:     return "Shared a song"
        case .playlist: return "Shared a playlist"
        case .mixtape:  return "Shared a mixtape"
        }
    }
}

/// Relative-time formatting for chat rows + bubbles. Parses the ISO timestamps
/// the backend returns (with or without fractional seconds).
enum ChatTime {
    // ISO8601DateFormatter is thread-safe for parsing/formatting, so sharing one
    // instance across actors is safe despite it not being marked Sendable.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? iso.date(from: s)
    }

    /// Compact relative label (e.g. "now", "5m", "3h", "2d", or a date).
    static func relative(_ s: String) -> String {
        guard let d = date(s) else { return "" }
        let secs = Date().timeIntervalSince(d)
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(Int(secs / 60))m" }
        if secs < 86_400 { return "\(Int(secs / 3600))h" }
        if secs < 604_800 { return "\(Int(secs / 86_400))d" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}
