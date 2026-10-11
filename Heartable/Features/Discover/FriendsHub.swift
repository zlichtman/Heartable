import SwiftUI
import UIKit

/// Friends hub rendered inline under the Discover "Friends" segment. Three sub-tabs:
///   • Feed   — a live "listening now" feed of what friends are playing
///   • Loves  — your accepted friends (with their current song when available)
///   • Find   — profile search and pending (incoming + sent) requests
///
/// Relies on the FriendRef-based `navigationDestination` declared by the enclosing
/// DiscoverView's NavigationStack, so taps push FriendProfileView.
@MainActor
struct FriendsHub: View {
    @Environment(ThemeStore.self) private var theme

    @State private var tab: Tab = .feed

    private enum Tab: String, CaseIterable, Identifiable {
        case feed = "Feed", loves = "Loves", find = "Find"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Friends section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch tab {
            case .feed: FeedTab()
            case .loves: LovesTab()
            case .find: FindTab()
            }
        }
    }
}

// MARK: - Feed

/// Friends' live presence followed by their durable, qualified listening events.
@MainActor
private struct FeedTab: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(FriendRelationships.self) private var relationships
    @Environment(BannerCenter.self) private var banners
    @Environment(FriendActivityRepository.self) private var activity

    @State private var live: [FriendNowPlayingDTO] = []
    @State private var loadedLive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !live.isEmpty {
                FriendsHubAtoms.sectionHeader("Listening now", theme: theme)
                ForEach(live) { friend in
                    FriendRows.feedRow(friend, theme: theme)
                }
            } else if !loadedLive {
                FriendsHubAtoms.sectionHeader("Listening now", theme: theme)
                FriendsHubAtoms.loadingCard(theme: theme)
            }

            FriendsHubAtoms.sectionHeader("Recently played", theme: theme)
            if activity.entries.isEmpty {
                if activity.isLoading {
                    FriendsHubAtoms.loadingCard(theme: theme)
                } else {
                    FriendsHubAtoms.emptyCard(
                        "Your friends’ qualified plays will collect here, even after the song ends.",
                        theme: theme
                    )
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(activity.entries) { entry in
                        FriendActivityCard(entry: entry)
                    }
                }

                if activity.canLoadMore {
                    Button {
                        Task { await loadOlder() }
                    } label: {
                        HStack(spacing: 8) {
                            if activity.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(activity.isLoadingMore ? "Loading…" : "Load older plays")
                        }
                        .font(Typography.semibold(13))
                        .foregroundStyle(theme.palette.rose)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            theme.palette.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(theme.palette.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(activity.isLoadingMore)
                    .padding(.top, 10)
                }
            }
        }
        .task(id: relationships.revision) { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool) async {
        async let liveTask: Void = loadLive()
        async let historyTask: Void = {
            if force {
                await activity.refresh()
            } else {
                await activity.load()
            }
        }()
        _ = await (liveTask, historyTask)
        if activity.errorMessage != nil {
            banners.error("Couldn’t refresh recent friend activity")
        }
    }

    private func loadLive() async {
        do {
            live = try await BackendAPI.shared.fetchFriendsNowPlaying()
            loadedLive = true
        } catch {
            // Keep the previous presence snapshot visible during transient errors.
            loadedLive = true
            banners.error("Couldn’t refresh who’s listening now")
        }
    }

    private func loadOlder() async {
        await activity.loadMore()
        if activity.errorMessage != nil {
            banners.error("Couldn’t load older friend activity")
        }
    }
}

// MARK: - Historical activity card

@MainActor
private struct FriendActivityCard: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(ProvidersStore.self) private var providers
    @Environment(FriendActivityRepository.self) private var activity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let entry: FriendActivityEntryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(
                value: FriendRef(
                    userId: entry.userId,
                    displayName: entry.displayName,
                    avatarUrl: entry.avatarUrl
                )
            ) {
                HStack(spacing: 10) {
                    AvatarCircle(
                        urlString: entry.avatarUrl,
                        name: entry.displayName,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.displayName ?? entry.handle ?? "Friend")
                            .font(Typography.semibold(14))
                            .foregroundStyle(theme.palette.text)
                            .lineLimit(2)
                        Text(relativeLong(entry.playedAt))
                            .font(Typography.body(11))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.palette.textMuted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this friend’s profile")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    artwork
                    trackText
                    Spacer(minLength: 6)
                    playButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        artwork
                        trackText
                    }
                    playButton
                }
            }

            reactions
        }
        .padding(14)
        .background(
            theme.palette.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var artwork: some View {
        ArtworkThumb(
            urlString: entry.albumArt,
            size: dynamicTypeSize.isAccessibilitySize ? 64 : 58,
            corner: 11
        )
    }

    private var trackText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.trackName)
                .font(Typography.semibold(15))
                .foregroundStyle(theme.palette.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let artist = entry.artist, !artist.isEmpty {
                Text(artist)
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var playButton: some View {
        if let track = playableTrack,
           providers.isConnected(track.providerID),
           ProviderPlayback.isPlayable(track.providerID) {
            Button {
                Task { await player.play(track) }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(theme.palette.rose, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(entry.trackName)")
        }
    }

    private var reactions: some View {
        ViewThatFits(in: .horizontal) {
            reactionRow
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6),
                    count: 2
                ),
                spacing: 6
            ) {
                reactionButtons
            }
        }
    }

    private var reactionRow: some View {
        HStack(spacing: 6) {
            reactionButtons
        }
    }

    @ViewBuilder
    private var reactionButtons: some View {
        ForEach(FriendActivityReaction.allCases, id: \.rawValue) { reaction in
            let count = entry.reactionCount(reaction)
            let selected = entry.viewerReaction == reaction
            Button {
                Task {
                    await activity.toggleReaction(
                        activityID: entry.id,
                        reaction: reaction
                    )
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: reaction.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                    if count > 0 {
                        Text("\(count)")
                            .font(Typography.semibold(11))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(
                    selected ? Color.white : theme.palette.textSecondary
                )
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selected ? theme.palette.rose : theme.palette.surface,
                    in: Capsule()
                )
                .overlay {
                    if !selected {
                        Capsule().stroke(theme.palette.border, lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(activity.reactingActivityIDs.contains(entry.id))
            .accessibilityLabel(
                "\(reaction.accessibilityName), \(count) reaction\(count == 1 ? "" : "s")"
            )
            .accessibilityValue(selected ? "Selected" : "Not selected")
        }
    }

    private var playableTrack: UnifiedTrack? {
        guard let uri = entry.trackUri,
              let providerRaw = uri.split(separator: ":", maxSplits: 1).first,
              let provider = ProviderID(rawValue: String(providerRaw)),
              provider != .heartable,
              let nativeID = uri.split(separator: ":").last.map(String.init),
              !nativeID.isEmpty else {
            return nil
        }
        let artist = entry.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UnifiedTrack(
            key: trackKey(provider, nativeID),
            providerID: provider,
            providerTrackID: nativeID,
            uri: uri,
            name: entry.trackName,
            artists: artist.map { [UnifiedArtist(id: $0, name: $0)] } ?? [],
            album: nil,
            albumArt: entry.albumArt.flatMap(URL.init(string:)),
            durationMs: entry.durationMs ?? 0
        )
    }
}

// MARK: - Loves (accepted friends)

@MainActor
private struct LovesTab: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(FriendRelationships.self) private var relationships
    @Environment(BannerCenter.self) private var banners
    @State private var friends: [FriendDTO] = []
    @State private var nowPlaying: [UUID: FriendNowPlayingDTO] = [:]
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FriendsHubAtoms.sectionHeader("Your friends", theme: theme)
            if friends.isEmpty {
                FriendsHubAtoms.emptyCard(
                    loaded ? "No friends yet. Head to Find to add someone."
                           : "Loading…", theme: theme)
            } else {
                ForEach(friends) { friend in row(friend) }
            }
        }
        .task(id: relationships.revision) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            async let f = BackendAPI.shared.fetchFriends()
            async let np = BackendAPI.shared.fetchFriendsNowPlaying()
            friends = try await f
            nowPlaying = Dictionary(
                (try await np).map { ($0.userId, $0) },
                uniquingKeysWith: { newer, _ in newer }
            )
            loaded = true
        } catch {
            // Preserve the last good list; an outage is not an empty social graph.
            banners.error("Couldn’t refresh friends")
        }
    }

    @ViewBuilder
    private func row(_ friend: FriendDTO) -> some View {
        if let uid = friend.profile?.userId {
            NavigationLink(value: FriendRef(userId: uid,
                                            displayName: friend.profile?.displayName,
                                            avatarUrl: friend.profile?.avatarUrl)) {
                HStack(spacing: 12) {
                    AvatarCircle(urlString: friend.profile?.avatarUrl,
                                 name: friend.profile?.displayName, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.profile?.displayName ?? friend.profile?.handle ?? "Friend")
                            .font(Typography.semibold(14))
                            .foregroundStyle(theme.palette.text).lineLimit(1)
                        Text(subtitle(uid))
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13)).foregroundStyle(theme.palette.textMuted)
                }
                .padding(12)
                .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(theme.palette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }

    private func subtitle(_ uid: UUID) -> String {
        guard let f = nowPlaying[uid], let name = f.trackName else { return "Not listening" }
        let prefix = f.isPlaying ? "▶ " : ""
        let artist = f.artist ?? ""
        return artist.isEmpty ? "\(prefix)\(name)" : "\(prefix)\(name) · \(artist)"
    }
}

// MARK: - Find

@MainActor
private struct FindTab: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(FriendRelationships.self) private var relationships
    @Environment(BannerCenter.self) private var banners

    @State private var incoming: [FriendDTO] = []
    @State private var sent: [FriendDTO] = []
    @State private var acting: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { AddFriendView() } label: { searchCard }
                .buttonStyle(.plain)

            if !incoming.isEmpty || !sent.isEmpty {
                FriendsHubAtoms.sectionHeader("Pending", theme: theme)
                ForEach(incoming) { req in incomingRow(req) }
                ForEach(sent) { req in sentRow(req) }
            }
        }
        .task(id: relationships.revision) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        async let i = BackendAPI.shared.listIncomingRequests()
        async let s = BackendAPI.shared.listSentRequests()
        incoming = await i
        sent = await s
    }

    private func respond(_ req: FriendDTO, accept: Bool) async {
        guard !acting.contains(req.id) else { return }
        acting.insert(req.id)
        defer { acting.remove(req.id) }
        do {
            try await BackendAPI.shared.respondToFriendRequest(id: req.id, accept: accept)
            incoming.removeAll { $0.id == req.id }
            relationships.markChanged()
            banners.success(accept ? "Friend request accepted" : "Friend request declined")
        } catch {
            banners.error(error.localizedDescription)
            await load()
        }
    }

    private func cancel(_ req: FriendDTO) async {
        guard !acting.contains(req.id) else { return }
        acting.insert(req.id)
        defer { acting.remove(req.id) }
        do {
            try await BackendAPI.shared.cancelFriendRequest(id: req.id)
            sent.removeAll { $0.id == req.id }
            relationships.markChanged()
            banners.success("Friend request canceled")
        } catch {
            banners.error(error.localizedDescription)
            await load()
        }
    }

    // MARK: rows / cards

    private var searchCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 42, height: 42).background(theme.palette.rose, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Search for a friend").font(Typography.semibold(15)).foregroundStyle(theme.palette.text)
                Text("By name or @handle").font(Typography.body(12)).foregroundStyle(theme.palette.textSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.palette.textMuted)
        }
        .padding(14)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(theme.palette.border, lineWidth: 1))
        .padding(.bottom, 10)
    }

    private func incomingRow(_ req: FriendDTO) -> some View {
        HStack(spacing: 10) {
            AvatarCircle(urlString: req.profile?.avatarUrl, name: req.profile?.displayName, size: 42)
            Text(req.profile?.displayName ?? req.profile?.handle ?? "Someone")
                .font(Typography.semibold(14)).foregroundStyle(theme.palette.text).lineLimit(1)
            Spacer(minLength: 4)
            Button("Accept") { Task { await respond(req, accept: true) } }
                .font(Typography.semibold(12)).foregroundStyle(.white)
                .padding(.vertical, 7).padding(.horizontal, 14).frame(minHeight: 44)
                .background(theme.palette.rose, in: Capsule())
                .disabled(acting.contains(req.id))
            Button("Decline") { Task { await respond(req, accept: false) } }
                .font(Typography.medium(12)).foregroundStyle(theme.palette.textSecondary)
                .padding(.vertical, 7).padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
                .disabled(acting.contains(req.id))
        }
        .buttonStyle(.plain).padding(.vertical, 8)
    }

    private func sentRow(_ req: FriendDTO) -> some View {
        HStack(spacing: 10) {
            AvatarCircle(urlString: req.profile?.avatarUrl, name: req.profile?.displayName, size: 42)
            Text(req.profile?.displayName ?? req.profile?.handle ?? "Someone")
                .font(Typography.semibold(14)).foregroundStyle(theme.palette.text).lineLimit(1)
            Spacer(minLength: 4)
            Button(acting.contains(req.id) ? "Canceling…" : "Cancel") {
                Task { await cancel(req) }
            }
            .font(Typography.medium(12))
            .foregroundStyle(theme.palette.textSecondary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
            .buttonStyle(.plain)
            .disabled(acting.contains(req.id))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Shared rows

@MainActor
private enum FriendRows {
    static func feedRow(_ f: FriendNowPlayingDTO, theme: ThemeStore) -> some View {
        NavigationLink(value: FriendRef(userId: f.userId, displayName: f.displayName, avatarUrl: f.avatarUrl)) {
            HStack(spacing: 12) {
                AvatarCircle(urlString: f.avatarUrl, name: f.displayName, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.displayName ?? "Friend")
                        .font(Typography.semibold(14)).foregroundStyle(theme.palette.text).lineLimit(1)
                    Text(line(f))
                        .font(Typography.body(12)).foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(relativeLong(f.updatedAt)).font(Typography.body(11)).foregroundStyle(theme.palette.textMuted)
            }
            .padding(12)
            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(theme.palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    static func line(_ f: FriendNowPlayingDTO) -> String {
        guard let name = f.trackName else { return "Not listening" }
        let prefix = f.isPlaying ? "▶ " : ""
        let artist = f.artist ?? ""
        return artist.isEmpty ? "\(prefix)\(name)" : "\(prefix)\(name) · \(artist)"
    }
}

// MARK: - Shared hub atoms

@MainActor
private enum FriendsHubAtoms {
    static func sectionHeader(_ text: String, theme: ThemeStore) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func emptyCard(_ text: String, theme: ThemeStore) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 24))
                .foregroundStyle(theme.palette.textMuted)
            Text(text)
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        )
    }

    static func loadingCard(theme: ThemeStore) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(theme.palette.rose)
            Text("Loading friend activity…")
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
