import SwiftUI

enum FriendProfileModuleLayout {
    static func visibleModules(
        from preferences: [ProfileModulePreferenceDTO]?
    ) -> [ProfileModuleID] {
        ProfileCurationDTO.normalizedModules(
            preferences ?? ProfileModulePreferenceDTO.defaults
        )
        .filter(\.isVisible)
        .map(\.module)
    }
}

/// A friend's profile — the music-social centerpiece a user lands on from the
/// friends feed, the now-playing feed, or search. A calm identity card groups
/// their avatar, name, service badges, live listening status, and the primary
/// friendship action. Below it:
/// their standing on the friends board, the songs in their rotation, mixtapes
/// they've shared with the viewer, and their links.
///
/// Every section reads real backend data (profiles, now_playing, friend_/song_
/// leaderboard, mixtape shares, friendships) and quietly hides when empty, so the
/// page is never blank while loading or for a sparse profile.
struct FriendProfileView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(FriendLinks.self) private var friendLinks
    @Environment(BannerCenter.self) private var banners
    @Environment(ChatStore.self) private var chats
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var avatarSize = 88

    let userId: UUID
    let displayName: String?
    let avatarUrl: String?

    @State private var profile: ProfileDTO?
    @State private var nowPlaying: FriendNowPlayingDTO?
    @State private var standing: LeaderboardEntryDTO?
    @State private var rank: Int?
    @State private var rotation: [SongLeaderboardEntryDTO] = []
    @State private var compatibility: FriendCompatibilityAvailability = .insufficient
    @State private var featuredPlaylists: [UnifiedPlaylist] = []
    @State private var visibleModules = FriendProfileModuleLayout.visibleModules(
        from: nil
    )
    @State private var sharedMixtapes: [MixtapeDTO] = []
    @State private var friendship: FriendshipState = .loading
    @State private var loading = true
    @State private var actionBusy = false
    @State private var confirmingRemoveFriend = false
    @State private var showingMixtapeComposer = false
    @State private var createdMixtapeID: UUID?

    /// Friendship relationship between the viewer and this profile.
    private enum FriendshipState: Equatable {
        case loading
        case unavailable
        case none
        case outgoing(UUID)
        case incoming(UUID)   // friendship row id, for accept/decline
        case friends(UUID)    // friendship row id, for remove
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                hero
                if !loading {
                    ForEach(visibleModules) { module in
                        moduleSection(module)
                    }
                    if profile == nil { unreachableNote }
                }
            }
            .padding(.bottom, 28)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingMixtapeComposer) {
            SharedMixtapeComposerSheet(
                friendID: userId,
                friendName: name
            ) { mixtapeID in
                createdMixtapeID = mixtapeID
            }
            .heartableSheetChrome()
        }
        .sheet(isPresented: $confirmingRemoveFriend) {
            HeartableDestructiveConfirmation(
                icon: "person.badge.minus",
                title: "Remove friend?",
                message: "\(name) will no longer appear in your friends, chats, or shared activity.",
                confirmTitle: "Remove friend",
                cancelTitle: "Stay friends",
                isBusy: actionBusy,
                onCancel: { confirmingRemoveFriend = false },
                onConfirm: {
                    guard case .friends(let id) = friendship else { return }
                    Task {
                        await remove(id: id)
                        confirmingRemoveFriend = false
                    }
                }
            )
        }
        .navigationDestination(item: $createdMixtapeID) { mixtapeID in
            MixtapeEditorView(mixtapeID: mixtapeID)
        }
    }

    // MARK: - Curated modules

    @ViewBuilder
    private func moduleSection(_ module: ProfileModuleID) -> some View {
        switch module {
        case .compatibility:
            if isFriend {
                FriendCompatibilityCard(
                    availability: compatibility,
                    friendName: name
                )
                .padding(.horizontal, 18)
            }
        case .featuredPlaylists:
            featuredPlaylistsSection
        case .listeningStats:
            if standing != nil { statsRow }
        case .topTracks:
            rotationSection
        case .sharedMixtapes:
            sharedMixtapesModule
        case .musicLinks:
            linksSection
        }
    }

    @ViewBuilder
    private var sharedMixtapesModule: some View {
        if isFriend {
            FriendMixtapeEntryCard(friendName: name) {
                showingMixtapeComposer = true
            }
            .padding(.horizontal, 18)
        }
        mixtapesSection
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    avatar
                    identityDetails
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    avatar
                    identityDetails
                    Spacer(minLength: 0)
                }
            }

            Divider().overlay(theme.palette.border)

            NowPlayingStrip(
                trackName: nowPlaying?.trackName,
                artist: nowPlaying?.artist,
                albumArt: nowPlaying?.albumArt,
                isPlaying: nowPlaying?.isPlaying ?? false,
                updatedAt: nowPlaying?.updatedAt
            )

            actions
        }
        .padding(16)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    private var identityDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name)
                .font(Typography.heading(28))
                .foregroundStyle(theme.palette.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(handleLine)
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            serviceRow
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        let size = min(avatarSize, 116)
        return AvatarCircle(urlString: profile?.avatarUrl ?? avatarUrl, name: name, size: size)
            .overlay(Circle().stroke(theme.palette.border, lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name)'s profile photo")
    }

    private var serviceRow: some View {
        HStack(spacing: 7) {
            HStack(spacing: -4) {
                ForEach(serviceBadges, id: \.self) { id in
                    ProviderBadge(id: id, size: 22, connected: true)
                        .overlay(Circle().stroke(theme.palette.card, lineWidth: 2))
                }
            }
            Text(serviceSummary)
                .font(Typography.medium(12))
                .foregroundStyle(theme.palette.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Music profile")
        .accessibilityValue(serviceSummary)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        Group {
            switch friendship {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading friendship")
                        .font(Typography.semibold(15))
                }
                .foregroundStyle(theme.palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(theme.palette.surface, in: Capsule())
                .accessibilityElement(children: .combine)
            case .unavailable:
                Button {
                    Task { await loadFriendState() }
                } label: {
                    outlinedButton("arrow.clockwise", "Retry friendship")
                }
                .buttonStyle(.plain)
            case .friends:
                actionPair {
                    NavigationLink {
                        ConversationView(friend: friendProfile, chats: chats)
                    } label: {
                        filledButton("bubble.left.fill", "Message")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens your conversation with \(name)")
                } secondary: {
                    friendsMenu
                }
            case .incoming(let id):
                actionPair {
                    Button {
                        Task { await respond(id: id, accept: true) }
                    } label: { filledButton("checkmark", "Accept request") }
                    .buttonStyle(.plain)
                } secondary: {
                    Button {
                        Task { await respond(id: id, accept: false) }
                    } label: { outlinedButton("xmark", "Decline") }
                    .buttonStyle(.plain)
                }
            case .outgoing(let id):
                Button {
                    Task { await cancel(id: id) }
                } label: {
                    outlinedButton("xmark", actionBusy ? "Canceling…" : "Cancel request")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Cancels your pending friend request to \(name)")
            case .none:
                Button {
                    Task { await sendRequest() }
                } label: { filledButton("person.badge.plus", "Add friend") }
                .buttonStyle(.plain)
                .accessibilityHint("Sends \(name) a friend request")
            }
        }
        .disabled(actionBusy)
        .opacity(actionBusy ? 0.7 : 1)
    }

    @ViewBuilder
    private func actionPair<Primary: View, Secondary: View>(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                primary().frame(maxWidth: .infinity)
                secondary().frame(maxWidth: .infinity)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    primary().frame(maxWidth: .infinity)
                    secondary().frame(maxWidth: .infinity)
                }
                VStack(spacing: 10) {
                    primary().frame(maxWidth: .infinity)
                    secondary().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var friendsMenu: some View {
        Button {
            confirmingRemoveFriend = true
        } label: {
            outlinedButton("checkmark", "Friends")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Friendship options")
        .accessibilityValue("Friends with \(name)")
    }

    private func filledButton(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.semibold(15))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 16)
        .background(theme.palette.rose, in: Capsule())
        .contentShape(Capsule())
    }

    private func outlinedButton(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.semibold(15))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.palette.text)
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 16)
        .background(theme.palette.surface, in: Capsule())
        .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
        .contentShape(Capsule())
    }

    // MARK: - Featured playlists

    @ViewBuilder
    private var featuredPlaylistsSection: some View {
        if !featuredPlaylists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    "Featured playlists",
                    subtitle: "Picked by \(name)"
                )

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 220 : 140),
                            spacing: 14
                        )
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(featuredPlaylists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CoverArt(
                                    url: playlist.image,
                                    corner: Theme.Radius.md,
                                    placeholder: "music.note.list"
                                )
                                .aspectRatio(1, contentMode: .fit)

                                Text(playlist.name)
                                    .font(Typography.semibold(14))
                                    .foregroundStyle(theme.palette.text)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 5) {
                                    ProviderBadge(id: playlist.providerID, size: 16)
                                    Text(playlist.owner ?? "Playlist")
                                        .font(Typography.body(11))
                                        .foregroundStyle(theme.palette.textMuted)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(playlist.name)
                        .accessibilityHint("Opens playlist")
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("On the board", subtitle: "Listening activity from the last 7 days")
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 96),
                        spacing: 10
                    )
                ],
                spacing: 10
            ) {
                if let rank {
                    statTile(value: "#\(rank)", label: "Rank",
                             systemImage: "trophy.fill", accent: theme.palette.rose)
                }
                statTile(value: "\(standing?.tracks ?? 0)", label: "Tracks",
                         systemImage: "music.note", accent: theme.palette.sky)
                statTile(value: "\(standing?.minutes ?? 0)", label: "Minutes",
                         systemImage: "clock.fill", accent: theme.palette.amber)
            }
        }
        .padding(.horizontal, 18)
    }

    private func statTile(value: String, label: String, systemImage: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(value)
                .font(Typography.heading(22))
                .foregroundStyle(theme.palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(Typography.medium(12))
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(14)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    // MARK: - In their rotation

    @ViewBuilder
    private var rotationSection: some View {
        if !rotation.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("In their rotation", subtitle: "Most played in the last 30 days")
                VStack(spacing: 0) {
                    ForEach(Array(rotation.enumerated()), id: \.element.id) { i, entry in
                        rotationRow(index: i + 1, entry: entry)
                        if i < rotation.count - 1 {
                            Divider().overlay(theme.palette.border).padding(.leading, 46)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(theme.palette.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private func rotationRow(index: Int, entry: SongLeaderboardEntryDTO) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                rotationIdentity(index: index, entry: entry)
                playCountBadge(entry.plays)
                    .padding(.leading, 34)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .rotationAccessibility(entry)
        } else {
            HStack(alignment: .center, spacing: 10) {
                rotationIdentity(index: index, entry: entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                playCountBadge(entry.plays)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .rotationAccessibility(entry)
        }
    }

    private func rotationIdentity(
        index: Int,
        entry: SongLeaderboardEntryDTO
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(Typography.semibold(13))
                .foregroundStyle(theme.palette.textMuted)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trackName ?? "Unknown track")
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.artist ?? "")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func playCountBadge(_ plays: Int) -> some View {
        Label(
            "\(plays) \(plays == 1 ? "play" : "plays")",
            systemImage: "play.fill"
        )
        .font(Typography.medium(12))
        .foregroundStyle(theme.palette.rose)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            theme.palette.rose.opacity(0.12),
            in: Capsule()
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Shared mixtapes

    @ViewBuilder
    private var mixtapesSection: some View {
        if !sharedMixtapes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Mixtapes for you", subtitle: "Shared with you by \(name)")
                    .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(sharedMixtapes) { mix in
                            NavigationLink { MixtapeEditorView(mixtapeID: mix.id) } label: {
                                mixtapeCard(mix)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(mix.title ?? "Mixtape")
                            .accessibilityHint("Opens this mixtape")
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func mixtapeCard(_ mix: MixtapeDTO) -> some View {
        let cardWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 172 : 148
        return VStack(alignment: .leading, spacing: 8) {
            CoverArt(url: mix.coverUrl.flatMap(URL.init(string:)), size: cardWidth,
                     corner: Theme.Radius.md, placeholder: "rectangle.stack.badge.play")
                .accessibilityHidden(true)
            Text(mix.title ?? "Mixtape")
                .font(Typography.semibold(14))
                .foregroundStyle(theme.palette.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: cardWidth, alignment: .leading)
            if let desc = mix.description, !desc.isEmpty {
                Text(desc)
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
    }

    // MARK: - Links

    @ViewBuilder
    private var linksSection: some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Listen elsewhere", subtitle: "Open \(name)'s music profile")
                VStack(spacing: 8) {
                    ForEach(links) { link in
                        Link(destination: link.url) {
                            HStack(spacing: 7) {
                                Image(systemName: link.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.palette.rose)
                                    .accessibilityHidden(true)
                                Text(link.label)
                                    .font(Typography.semibold(15))
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.palette.textMuted)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(theme.palette.text)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(
                                theme.palette.card,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .stroke(theme.palette.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in another app")
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - States / atoms

    private var unreachableNote: some View {
        Text("We couldn't load the rest of this profile right now. Pull to try again.")
            .font(Typography.body(13))
            .foregroundStyle(theme.palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Typography.heading(20))
                .foregroundStyle(theme.palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived

    private var name: String {
        profile?.displayName ?? displayName ?? "Friend"
    }

    private var handleLine: String {
        if let h = profile?.handle, !h.isEmpty { return "@\(h)" }
        if let s = profile?.spotifyId, !s.isEmpty { return "@\(s)" }
        return "on Heartable"
    }

    private var serviceBadges: [ProviderID] {
        var ids: [ProviderID] = [.heartable]
        if let s = profile?.spotifyId, !s.isEmpty { ids.append(.spotify) }
        return ids
    }

    private var serviceSummary: String {
        serviceBadges
            .map { $0 == .heartable ? "Heartable" : (ProviderCatalog.entry($0)?.label ?? $0.rawValue) }
            .joined(separator: " · ")
    }

    private var friendProfile: ProfileDTO {
        profile ?? ProfileDTO(userId: userId, spotifyId: nil,
                              displayName: displayName, avatarUrl: avatarUrl,
                              handle: nil, shareCode: nil)
    }

    private var isFriend: Bool {
        if case .friends = friendship { return true }
        return false
    }

    private struct ProfileLink: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let icon: String
        let url: URL
    }

    /// Currently derived from the one friend-visible link we can read (their
    /// Spotify user id on `profiles`). Real per-service `profile_links` await a
    /// friend-scoped read on `BackendAPI` (see the note in the change summary).
    private var links: [ProfileLink] {
        var out: [ProfileLink] = []
        if let s = profile?.spotifyId, !s.isEmpty,
           let url = URL(string: "https://open.spotify.com/user/\(s)") {
            out.append(ProfileLink(label: "Spotify", icon: "music.note", url: url))
        }
        return out
    }

    // MARK: - Load

    private func load() async {
        let api = BackendAPI.shared
        async let profileTask = api.getMyProfile(userID: userId)
        async let npTask = api.getFriendsNowPlaying()
        async let boardTask = api.getFriendLeaderboard(windowDays: 7)
        async let rotationTask = api.getSongLeaderboard(windowDays: 30)
        async let mixTask = api.listMixtapes()
        async let curationTask = api.getProfileCuration(userID: userId)

        profile = try? await profileTask

        nowPlaying = await npTask.first { $0.userId == userId && $0.trackName != nil }

        let board = await boardTask
        standing = nil
        rank = nil
        if let idx = board.firstIndex(where: { $0.userId == userId }) {
            standing = board[idx]
            rank = idx + 1
        }

        let uidKey = userId.uuidString.lowercased()
        let songBoard = await rotationTask
        rotation = Array(songBoard
            .filter { entry in entry.contributors.contains { ($0.userId ?? "").lowercased() == uidKey } }
            .prefix(6))
        if let viewerID = AccountSessionStore.currentOwnerID {
            compatibility = FriendCompatibilityAvailability.evaluate(
                entries: songBoard,
                viewerID: viewerID,
                friendID: userId
            )
        } else {
            compatibility = .insufficient
        }

        sharedMixtapes = await mixTask.shared.filter { $0.owner == userId }
        let curation = await curationTask
        featuredPlaylists = curation?.playlists.map(\.unified) ?? []
        visibleModules = FriendProfileModuleLayout.visibleModules(
            from: curation?.modules
        )

        await loadFriendState()
        loading = false
    }

    private func loadFriendState() async {
        do {
            switch try await BackendAPI.shared.relationship(with: userId) {
            case .none: friendship = .none
            case .outgoing(let id): friendship = .outgoing(id)
            case .incoming(let id): friendship = .incoming(id)
            case .friends(let id): friendship = .friends(id)
            case .blocked: friendship = .unavailable
            }
        } catch {
            friendship = .unavailable
            banners.error("Couldn’t load friendship status")
        }
    }

    private func respond(id: UUID, accept: Bool) async {
        guard !actionBusy else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            try await BackendAPI.shared.respondToFriendRequest(id: id, accept: accept)
            friendLinks.markRelationshipsChanged()
            banners.success(accept ? "Friend request accepted" : "Friend request declined")
            await loadFriendState()
        } catch {
            banners.error(error.localizedDescription)
        }
    }

    private func sendRequest() async {
        guard !actionBusy else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            let outcome = try await BackendAPI.shared.sendFriendRequest(addresseeID: userId)
            switch outcome {
            case .sent:
                banners.success("Friend request sent")
            case .alreadyFriends:
                banners.info("You’re already friends")
            case .outgoingPending:
                banners.info("Friend request already pending")
            case .incomingPending:
                banners.info("They already sent you a friend request")
            case .blocked:
                banners.error("This profile isn’t available to add")
            }
            friendLinks.markRelationshipsChanged()
            await loadFriendState()
        } catch {
            banners.error(error.localizedDescription)
        }
    }

    private func cancel(id: UUID) async {
        guard !actionBusy else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            try await BackendAPI.shared.cancelFriendRequest(id: id)
            friendLinks.markRelationshipsChanged()
            banners.success("Friend request canceled")
            await loadFriendState()
        } catch {
            banners.error(error.localizedDescription)
        }
    }

    private func remove(id: UUID) async {
        guard !actionBusy else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            try await BackendAPI.shared.removeFriend(id: id)
            friendLinks.markRelationshipsChanged()
            banners.success("Friend removed")
            await loadFriendState()
        } catch {
            banners.error(error.localizedDescription)
        }
    }
}

private extension View {
    func rotationAccessibility(_ entry: SongLeaderboardEntryDTO) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.trackName ?? "Unknown track")
            .accessibilityValue(
                [entry.artist, "\(entry.plays) \(entry.plays == 1 ? "play" : "plays")"]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            )
    }
}
