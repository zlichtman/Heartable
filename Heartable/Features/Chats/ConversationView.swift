import SwiftUI

/// A single chat thread with one friend. Bubbles are right-aligned/rose for my
/// messages, left-aligned/surface for theirs. Attachments (song/playlist/
/// mixtape) render as a tappable card. The input bar sends text; the attach
/// affordance shares the currently-playing song (read-only PlayerStore).
struct ConversationView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let friend: ProfileDTO
    let chats: ChatStore

    @State private var draft = ""
    /// My own id, resolved once so bubbles can be sided without async in the body.
    @State private var myID: UUID?

    private var friendName: String { friend.displayName ?? friend.handle ?? "Friend" }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            messageList
            inputBar
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            myID = await chats.resolveCurrentUserID()
            chats.setSceneActive(scenePhase == .active)
            chats.open(friend)
        }
        .onChange(of: scenePhase) { _, phase in
            chats.setSceneActive(phase == .active)
        }
        .onDisappear {
            chats.close()
            Task { await chats.loadConversations() }
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(spacing: 12) {
            HeartableNavigationButton(kind: .back, action: dismiss.callAsFunction)
            AvatarCircle(urlString: friend.avatarUrl, name: friendName, size: 34)
            Text(friendName)
                .font(Typography.semibold(18))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.palette.bg)
    }

    // MARK: - Messages

    private var messageList: some View {
        Group {
            if chats.loadingMessages, chats.messages.isEmpty {
                ProgressView()
                    .tint(theme.palette.rose)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chats.messages.isEmpty, chats.threadError != nil {
                threadErrorState
            } else if chats.messages.isEmpty {
                emptyThreadState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(chats.messages) { msg in
                                MessageBubble(
                                    message: msg,
                                    isMine: msg.senderId == myID
                                )
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: chats.messages.count) {
                        if let last = chats.messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let last = chats.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var emptyThreadState: some View {
        VStack(spacing: 10) {
            AvatarCircle(
                urlString: friend.avatarUrl,
                name: friendName,
                size: 58
            )
            Text("Start a conversation")
                .font(Typography.semibold(17))
                .foregroundStyle(theme.palette.text)
            Text("Share a song or say hello to \(friendName).")
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var threadErrorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(theme.palette.rose)
            Text("Messages couldn’t load")
                .font(Typography.semibold(17))
                .foregroundStyle(theme.palette.text)
            Text(chats.threadError ?? "Try again in a moment.")
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                chats.clearThreadError()
                Task { await chats.refreshOpenThread() }
            }
            .font(Typography.semibold(14))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(theme.palette.rose, in: Capsule())
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.palette.border)
            HStack(spacing: 10) {
                nowPlayingAttachButton

                TextField("Message", text: $draft, axis: .vertical)
                    .font(Typography.body(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(theme.palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.full, style: .continuous))
                    .onSubmit(sendText)

                Button(action: sendText) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? theme.palette.rose : theme.palette.textMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(theme.palette.bg)
    }

    /// Share the currently-playing song. Hidden when nothing is playing.
    @ViewBuilder
    private var nowPlayingAttachButton: some View {
        if player.now != nil {
            Button {
                if let now = player.now {
                    Task {
                        let sent = await chats.sendNowPlaying(now)
                        if !sent {
                            banners.error(
                                chats.threadError ?? "Could not share this song"
                            )
                        }
                    }
                }
            } label: {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.palette.rose)
                    .frame(width: 44, height: 44)
                    .background(theme.palette.surface)
                    .clipShape(Circle())
            }
            .disabled(chats.sending)
            .accessibilityLabel("Share now playing")
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chats.sending
    }

    private func sendText() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        Task {
            let sent = await chats.sendText(body)
            if !sent {
                if draft.isEmpty { draft = body }
                banners.error(
                    chats.threadError ?? "Could not send message"
                )
            }
        }
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    @Environment(ThemeStore.self) private var theme
    let message: MessageDTO
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(isMine ? theme.palette.rose : theme.palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.kind {
        case .text:
            Text(message.body ?? "")
                .font(Typography.body(15))
                .foregroundStyle(isMine ? .white : theme.palette.text)
        case .song, .playlist, .mixtape:
            AttachmentCard(message: message, isMine: isMine)
        }
    }
}

// MARK: - Attachment card

/// Renders any attachment kind we receive (song/playlist/mixtape) as a card.
/// Song cards route through Heartable's unified player so a conversation never
/// has to eject the listener into a provider app.
private struct AttachmentCard: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(BannerCenter.self) private var banners
    let message: MessageDTO
    let isMine: Bool

    private var fg: Color { isMine ? .white : theme.palette.text }
    private var fgSecondary: Color { isMine ? Color.white.opacity(0.85) : theme.palette.textSecondary }

    @ViewBuilder
    var body: some View {
        if playableTrack != nil {
            Button(action: tap) {
                cardLabel
            }
            .buttonStyle(.plain)
            .accessibilityHint("Plays this song in Heartable")
        } else {
            cardLabel
        }
    }

    private var cardLabel: some View {
        HStack(spacing: 10) {
            CoverArt(url: artURL, size: 46, corner: Theme.Radius.sm)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel)
                    .font(Typography.body(11))
                    .foregroundStyle(fgSecondary)
                Text(title)
                    .font(Typography.semibold(14))
                    .foregroundStyle(fg)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.body(12))
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fgSecondary)
        }
        .frame(minWidth: 180)
    }

    private func tap() {
        guard message.kind == .song, let track = playableTrack else { return }
        Task {
            await player.play(track)
            if let feedback = player.feedbackMessage {
                banners.error(feedback)
            }
        }
    }

    private var playableTrack: UnifiedTrack? {
        guard let song = message.payload?.song else { return nil }
        let inferredProvider = song.uri
            .split(separator: ":", maxSplits: 1)
            .first
            .flatMap { ProviderID(rawValue: String($0)) }
        guard let provider = song.providerID.flatMap(ProviderID.init(rawValue:))
                ?? inferredProvider,
              provider != .heartable else { return nil }

        let inferredTrackID = song.uri
            .split(separator: ":")
            .last
            .map(String.init)
        guard let providerTrackID = song.providerTrackID ?? inferredTrackID,
              !providerTrackID.isEmpty else { return nil }
        let artist = song.artist ?? ""
        return UnifiedTrack(
            key: trackKey(provider, providerTrackID),
            providerID: provider,
            providerTrackID: providerTrackID,
            uri: song.uri,
            name: song.name ?? "Unknown song",
            artists: [UnifiedArtist(id: artist, name: artist)],
            album: nil,
            albumArt: song.art.flatMap(URL.init(string:)),
            durationMs: song.durationMs ?? 0
        )
    }

    private var kindLabel: String {
        switch message.kind {
        case .song: return "Song"
        case .playlist: return "Playlist"
        case .mixtape: return "Mixtape"
        case .text: return ""
        }
    }

    private var glyph: String {
        switch message.kind {
        case .song: return "play.fill"
        case .playlist: return "music.note.list"
        case .mixtape: return "cassette.tape"
        case .text: return ""
        }
    }

    private var title: String {
        switch message.kind {
        case .song:     return message.payload?.song?.name ?? "Unknown song"
        case .playlist: return message.payload?.playlist?.name ?? "Unknown playlist"
        case .mixtape:  return message.payload?.mixtape?.name ?? "Unknown mixtape"
        case .text:     return ""
        }
    }

    private var subtitle: String? {
        switch message.kind {
        case .song:     return message.payload?.song?.artist
        case .playlist, .mixtape, .text: return nil
        }
    }

    private var artURL: URL? {
        let s: String?
        switch message.kind {
        case .song:     s = message.payload?.song?.art
        case .playlist: s = message.payload?.playlist?.image
        case .mixtape, .text: s = nil
        }
        guard let s else { return nil }
        return URL(string: s)
    }
}
