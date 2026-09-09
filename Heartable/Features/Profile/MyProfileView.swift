import SwiftUI

/// The signed-in user's public profile preview. It shares the same calm identity
/// hierarchy as friend profiles, while exposing one clear Edit route and showing
/// only profile-relevant content: listening status, chosen playlists, a concise
/// taste snapshot, and recent activity.
struct MyProfileView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(AuthStore.self) private var auth
    @Environment(MeStore.self) private var me
    @Environment(PlayerStore.self) private var player
    @Environment(ProvidersStore.self) private var providers
    @Environment(TopTracksRepository.self) private var topTracks
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .title) private var avatarSize = 88

    @State private var history: [PlayEntryDTO] = []
    @State private var loading = true
    @State private var curationErrorMessage: String?

    private var liveProviders: [ProviderID] {
        ProviderCatalog.all
            .filter { $0.status == .live && providers.isConnected($0.id) }
            .map(\.id)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                identityCard

                if loading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(theme.palette.rose)
                        Spacer()
                    }
                    .padding(.top, 24)
                } else {
                    ForEach(visibleModules) { preference in
                        profileModule(preference.module)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable {
            await load(force: true)
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
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
            listeningStatus

            NavigationLink { EditProfileView() } label: {
                Label("Edit profile", systemImage: "square.and.pencil")
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(theme.palette.surface, in: Capsule())
                    .overlay {
                        Capsule().stroke(theme.palette.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            theme.palette.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    private var avatar: some View {
        let size = min(avatarSize, 116)
        return AvatarCircle(
            urlString: me.avatarUrlString,
            name: me.displayName,
            size: size
        )
        .overlay(Circle().stroke(theme.palette.border, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profile photo")
    }

    private var identityDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(me.displayName)
                .font(Typography.heading(28))
                .foregroundStyle(theme.palette.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Text(me.handle.map { "@\($0)" } ?? "Add a handle")
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(2)

            if !liveProviders.isEmpty {
                HStack(spacing: 7) {
                    HStack(spacing: -4) {
                        ForEach(liveProviders) { id in
                            ProviderBadge(id: id, size: 22, connected: true)
                                .overlay(Circle().stroke(theme.palette.card, lineWidth: 2))
                        }
                    }
                    Text(serviceSummary)
                        .font(Typography.medium(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .lineLimit(2)
                }
                .padding(.top, 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Connected music services")
                .accessibilityValue(serviceSummary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var listeningStatus: some View {
        if let now = player.now {
            HStack(spacing: 12) {
                CoverArt(url: now.artworkURL, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: now.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityHidden(true)
                        Text(now.isPlaying ? "LISTENING NOW" : "PAUSED")
                            .font(Typography.semibold(10))
                            .tracking(0.8)
                    }
                    .foregroundStyle(now.isPlaying ? theme.palette.rose : theme.palette.textMuted)

                    Text(now.name)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(1)
                    Text(now.artist)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(now.isPlaying ? "Listening now" : "Paused")
            .accessibilityValue("\(now.name), \(now.artist)")
        } else {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.palette.textMuted)
                    .accessibilityHidden(true)
                Text("Not listening right now")
                    .font(Typography.medium(13))
                    .foregroundStyle(theme.palette.textMuted)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Featured playlists

    private var visibleModules: [ProfileModulePreferenceDTO] {
        me.profileModules.filter(\.isVisible)
    }

    @ViewBuilder
    private func profileModule(_ module: ProfileModuleID) -> some View {
        switch module {
        case .compatibility:
            // Compatibility is computed against the viewer on friend profiles.
            EmptyView()
        case .featuredPlaylists:
            featuredSection
        case .listeningStats:
            recentSection
        case .topTracks:
            tasteSection
        case .sharedMixtapes, .musicLinks:
            // These friend-specific sections hide naturally when previewing self.
            EmptyView()
        }
    }

    private var featuredPlaylists: [UnifiedPlaylist] {
        me.featuredPlaylists
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !featuredPlaylists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    "Featured playlists",
                    subtitle: "Chosen for your public profile"
                )

                let columns = [
                    GridItem(
                        .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 220 : 140),
                        spacing: 14
                    )
                ]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(featuredPlaylists) { playlist in
                        featuredPlaylistCard(playlist)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    "Featured playlists",
                    subtitle: "Choose what friends see first"
                )
                if let curationErrorMessage {
                    Text(curationErrorMessage)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NavigationLink { EditProfileView() } label: {
                    Label("Choose playlists", systemImage: "plus")
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.rose)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(theme.palette.card)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(theme.palette.border, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func featuredPlaylistCard(_ playlist: UnifiedPlaylist) -> some View {
        NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
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

    // MARK: - Taste / activity

    @ViewBuilder
    private var tasteSection: some View {
        let top = Array(topTracks.tracks(for: .mediumTerm).prefix(5))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(
                    "In heavy rotation",
                    subtitle: "A snapshot of what you play most"
                )
                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, track in
                        let plays = topTracks.playCount(for: track, range: .mediumTerm)
                        UnifiedTrackRow(
                            track: track,
                            rank: index + 1,
                            statText: "\(plays) play\(plays == 1 ? "" : "s")",
                            isEnabled: providers.isConnected(track.providerID)
                                && ProviderPlayback.isPlayable(track.providerID)
                        ) {
                            Task { await player.play(track) }
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(
                    theme.palette.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                sectionHeader(
                    "Recent listening",
                    subtitle: "Your latest plays"
                )
                Spacer(minLength: 12)
                NavigationLink { ListeningHistoryView() } label: {
                    Text("See all")
                        .font(Typography.semibold(12))
                        .foregroundStyle(theme.palette.rose)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            if history.isEmpty {
                Text("Nothing played yet.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        theme.palette.card,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.prefix(5)).enumerated(), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            CoverArt(
                                url: entry.albumArt.flatMap(URL.init(string:)),
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.trackName ?? "Unknown")
                                    .font(Typography.semibold(14))
                                    .foregroundStyle(theme.palette.text)
                                    .lineLimit(1)
                                Text(entry.artist ?? "")
                                    .font(Typography.body(12))
                                    .foregroundStyle(theme.palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)

                        if index < min(history.count, 5) - 1 {
                            Divider()
                                .overlay(theme.palette.border)
                                .padding(.leading, 68)
                        }
                    }
                }
                .background(
                    theme.palette.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Typography.heading(20))
                .foregroundStyle(theme.palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var serviceSummary: String {
        liveProviders
            .map { ProviderCatalog.entry($0)?.label ?? $0.rawValue }
            .joined(separator: " · ")
    }

    private func load(force: Bool = false) async {
        guard let userID = auth.userID else { return }
        loading = !me.hasLoadedFeaturedPlaylists && history.isEmpty
        curationErrorMessage = nil

        async let historyTask = BackendAPI.shared.fetchPlayHistory(limit: 30)
        async let meTask: Void = me.load(userID: userID, force: force)
        async let topTask: Void = topTracks.load(
            range: .mediumTerm,
            providers: providers.connected,
            force: force
        )

        do {
            _ = try await me.loadFeaturedPlaylists(userID: userID, force: force)
        } catch {
            curationErrorMessage = "Couldn’t refresh featured playlists. Try again from Edit Profile."
        }
        history = await historyTask
        await meTask
        await topTask
        loading = false
    }
}
