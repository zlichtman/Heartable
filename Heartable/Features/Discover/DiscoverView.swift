import SwiftUI

/// Discover (Heartable) tab. An in-content header, then a single segmented control
/// (Top Tracks | Song Board | Friends) so the screen stays bounded. Folds in what
/// used to be a separate Stats screen, and now hosts the Friends hub inline.
/// Ported from the RN HeartableScreen.
struct DiscoverView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(ProvidersStore.self) private var providers
    @Environment(TopTracksRepository.self) private var topTracks
    @Environment(FriendLinks.self) private var friendLinks

    /// Owned by AppTabView so re-tapping the tab pops back to root.
    @Binding var navPath: NavigationPath
    var friendsRequestID: UUID? = nil

    @State private var store = DiscoverStore()
    @State private var mode: Mode = .top
    @State private var topSelection = TopTracksSelection()
    @State private var topSelectionRequestID: UUID?
    @State private var topRange: StatRange = .shortTerm
    @State private var boardWindow: Int = 7

    private enum Mode: String, CaseIterable, Identifiable {
        case top = "Top Tracks", board = "Song Board", friends = "Friends"
        var id: String { rawValue }
    }

    private static let windows: [(value: Int, label: String)] =
        [(7, "Week"), (30, "Month"), (3650, "All")]
    private static let medal: [Color] =
        [Color(hex: 0xffd24a), Color(hex: 0xcdd3da), Color(hex: 0xe0935a)]

    private var selectableTopSources: [TopTracksSource] {
        TopTracksSource.selectableSources(
            connectedProviderIDs: providers.connectedIDs
        )
    }

    private var topSource: TopTracksSource {
        topSelection.source
            ?? TopTracksSelection.preferredOrder(selectableTopSources).first
            ?? .heartable
    }

    private var topSourceBinding: Binding<TopTracksSource> {
        Binding(get: { topSource }, set: { topSelection.select($0) })
    }

    private func resolveTopSource() {
        topSelection.resolve(
            availableSources: selectableTopSources,
            populatedSources: Set(selectableTopSources.filter {
                !topTracks.tracks(for: topRange, source: $0).isEmpty
            })
        )
    }

    /// One stable request identity replaces the overlapping mode/range/window
    /// tasks that could issue the same initial request twice.
    private var loadRequest: String {
        switch mode {
        case .top:
            // Automatic fallback is part of this request, not a second task that
            // cancels the first one halfway through publishing its cache.
            "top:\(topSelection.explicitSource?.rawValue ?? "auto"):\(topRange.rawValue):\(providers.refreshGeneration)"
        case .board: "board:\(boardWindow)"
        case .friends: "friends"
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                theme.palette.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    // Mode + range stay pinned above the list as it scrolls.
                    VStack(spacing: 10) {
                        modePicker
                        rangePicker
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if mode == .top, !store.friendsNow.isEmpty { friendsStrip }
                            content
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: FriendRef.self) { ref in
                FriendProfileView(userId: ref.userId,
                                  displayName: ref.displayName,
                                  avatarUrl: ref.avatarUrl)
            }
            .navigationDestination(for: AddFriendRoute.self) { _ in
                AddFriendView()
            }
            .task(id: friendLinks.relationshipRevision) { await store.loadFriends() }
            .task(id: loadRequest) { await reloadMode() }
            .onChange(of: friendsRequestID, initial: true) {
                if friendsRequestID != nil { mode = .friends }
            }
            .refreshable {
                await store.loadFriends()
                await reloadMode(force: true)
            }
        }
    }

    private func reloadMode(force: Bool = false) async {
        switch mode {
        case .top:
            let requestID = UUID()
            topSelectionRequestID = requestID
            defer {
                if topSelectionRequestID == requestID { topSelectionRequestID = nil }
            }
            // Disk cache is independent of provider discovery, so render it
            // immediately while the authoritative connection probe completes.
            await topTracks.prepare()
            guard !Task.isCancelled else { return }
            resolveTopSource()
            guard providers.hasRefreshed else { return }
            let selected = topSource
            await topTracks.load(
                range: topRange,
                source: selected,
                providers: providers.connected,
                force: force
            )
            guard !Task.isCancelled, topSelectionRequestID == requestID,
                  topSelection.explicitSource == nil,
                  topTracks.tracks(for: topRange, source: selected).isEmpty else { return }

            // A connected service can still have no ranking. Try the other real
            // sources only when needed; never manufacture stats from a library.
            for fallback in TopTracksSelection.preferredOrder(selectableTopSources)
                where fallback != selected {
                await topTracks.load(
                    range: topRange, source: fallback,
                    providers: providers.connected, force: force
                )
                guard !Task.isCancelled, topSelectionRequestID == requestID,
                      topSelection.explicitSource == nil else { return }
                resolveTopSource()
                if !topTracks.tracks(for: topRange, source: topSource).isEmpty { break }
            }
        case .board: await store.loadBoard(windowDays: boardWindow)
        case .friends: break  // FriendsHub owns its own loading
        }
    }

    // MARK: Header

    private var header: some View {
        HeartablePageHeader(tab: .discover)
    }

    // MARK: Friends strip

    private var friendsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Friends now playing")
                    .font(Typography.semibold(13))
                    .foregroundStyle(theme.palette.textMuted)
                Spacer()
                Button { mode = .friends } label: {
                    Text("All").font(Typography.semibold(12))
                        .foregroundStyle(theme.palette.rose)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.friendsNow.prefix(10)) { f in
                        NavigationLink(value: FriendRef(userId: f.userId,
                                                        displayName: f.displayName,
                                                        avatarUrl: f.avatarUrl)) {
                            friendChip(f)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 16)
            }
        }
    }

    private func friendChip(_ f: FriendNowPlayingDTO) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AvatarCircle(urlString: f.avatarUrl, name: f.displayName, size: 64)
                if f.isPlaying {
                    Circle().fill(theme.palette.rose)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(theme.palette.bg, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            Text(f.displayName ?? "Friend")
                .font(Typography.semibold(12))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
            Text(f.trackName ?? "no song")
                .font(Typography.body(10))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 80)
    }

    // MARK: Pickers

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var rangePicker: some View {
        switch mode {
        case .top:
            VStack(alignment: .leading, spacing: 8) {
                Picker("Stats source", selection: topSourceBinding) {
                    ForEach(selectableTopSources) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Chooses which service supplies this ranking")

                Picker("Range", selection: $topRange) {
                    ForEach(StatRange.allCases) { range in
                        Text(range.compactLabel).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }
        case .board:
            Picker("Window", selection: $boardWindow) {
                ForEach(Self.windows, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
        case .friends:
            EmptyView()  // FriendsHub renders its own sub-segments
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .friends:
            FriendsHub()
        case .top:
            if (!providers.hasRefreshed || topSelectionRequestID != nil
                || topTracks.isInitiallyLoading(topRange, source: topSource)),
               topTracks.tracks(for: topRange, source: topSource).isEmpty {
                ProgressView()
                    .tint(theme.palette.rose)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if topTracks.isRefreshing(topRange, source: topSource),
                       !topTracks.tracks(for: topRange, source: topSource).isEmpty {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(theme.palette.rose)
                            Text("Checking for updates")
                                .font(Typography.body(11))
                                .foregroundStyle(theme.palette.textMuted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    topList
                }
            }
        case .board:
            if store.loadingBoard {
                ProgressView()
                    .tint(theme.palette.rose)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                boardList
            }
        }
    }

    @ViewBuilder
    private var topList: some View {
        let tracks = topTracks.tracks(for: topRange, source: topSource)
        if tracks.isEmpty {
            emptyText(topEmptyMessage)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                    let plays = topTracks.playCount(
                        for: track,
                        range: topRange,
                        source: topSource
                    )
                    UnifiedTrackRow(
                        track: track,
                        rank: i + 1,
                        statText: topSource == .heartable
                            ? "\(plays) play\(plays == 1 ? "" : "s")"
                            : nil,
                        isEnabled: providers.isConnected(track.providerID)
                            && ProviderPlayback.isPlayable(track.providerID)
                    ) {
                        Task { await player.play(track) }
                    }
                }
            }
        }
    }

    private var topEmptyMessage: String {
        switch topSource {
        case .heartable:
            "Songs you play through Heartable will appear here."
        case .spotify:
            "No Spotify stats yet."
        case .apple:
            "No Apple Music stats yet."
        }
    }

    @ViewBuilder
    private var boardList: some View {
        if store.songBoard.isEmpty {
            emptyText("No plays in this window. Listen with friends to fill the board.")
        } else {
            LazyVStack(spacing: 6) {
                ForEach(Array(store.songBoard.prefix(50).enumerated()), id: \.element.id) { i, entry in
                    boardRow(entry, index: i)
                }
            }
        }
    }

    private func boardRow(_ entry: SongLeaderboardEntryDTO, index: Int) -> some View {
        let isMedal = index < 3
        let rankColor = isMedal ? Self.medal[index] : theme.palette.textMuted
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(Typography.semibold(16))
                .foregroundStyle(rankColor)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trackName ?? "Unknown track")
                    .font(Typography.semibold(14))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                Text("\(entry.artist ?? "Unknown") · \(entry.plays) play\(entry.plays == 1 ? "" : "s")")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isMedal {
                Image(systemName: "trophy.fill").foregroundStyle(Self.medal[index])
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, isMedal ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(isMedal ? Self.medal[index] : .clear, lineWidth: 1)
        )
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(Typography.body(13))
            .foregroundStyle(theme.palette.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

/// A friend reference for navigation into FriendProfileView. Hashable so it can
/// drive a `navigationDestination(for:)`.
struct FriendRef: Hashable {
    let userId: UUID
    let displayName: String?
    let avatarUrl: String?
}

// NOTE: AvatarCircle / ArtworkThumb / relativeShort / relativeLong are shared
// social atoms defined in FriendsView.swift (same module). Medal colors use the
// existing global Color(hex:) initializer from Theme.swift to match the RN palette.
// NOTE: The "Friends" segment renders FriendsHub (FriendsHub.swift) inline; the
// old toolbar Friends/AddFriend buttons are gone. FriendsView.swift is no longer
// reached from here but is kept intact; FriendProfileView/AddFriendView remain
// reachable (AddFriendView via the Sent sub-tab, profiles via FriendRef nav).
