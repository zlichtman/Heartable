import SwiftUI

/// Inside-a-playlist view, laid out like Spotify: a large centered cover at the
/// top, the name + description + owner centered beneath it, and a circular Play
/// button anchored top-right of a controls row. The hero scrolls away with the
/// list (it's the List's first section). Shuffle mode is whatever's active in
/// `prefs`; the Play button plays the first track in that order. Ported from the
/// RN LibraryPlaylistScreen.
struct PlaylistDetailView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs
    @Environment(LibrarySortStore.self) private var sortStore
    @Environment(PlaylistTracksRepository.self) private var playlistTracks

    let playlist: UnifiedPlaylist

    /// True once the hero has scrolled off — the playlist name then takes over
    /// the nav bar (the Apple Music handoff), so context is never lost.
    @State private var showBarTitle = false
    /// Display-only ordering of the visible rows. Separate from playback order,
    /// which stays driven by `prefs.mode` / `prefs.order(...)`.
    @State private var sort: TrackSort = .original
    @State private var sortReversed = false
    @State private var showingSortOptions = false

    private var tracks: [UnifiedTrack] {
        playlistTracks.tracks(for: playlist)
    }

    private var loading: Bool {
        tracks.isEmpty
            && !playlistTracks.didFail(playlist)
            && (
                !playlistTracks.hasResolved(playlist)
                    || playlistTracks.isInitiallyLoading(playlist)
            )
    }

    /// How the visible track rows are ordered (not the playback order).
    private enum TrackSort: String, CaseIterable, Identifiable {
        case original = "Original order"
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case dateAdded = "Date added"
        case duration = "Duration"

        var id: String { rawValue }
        var short: String {
            switch self {
            case .original: "Order"
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .dateAdded: "Added"
            case .duration: "Time"
            }
        }
        var icon: String {
            switch self {
            case .original: "list.number"
            case .title: "textformat"
            case .artist: "music.mic"
            case .album: "square.stack"
            case .dateAdded: "calendar"
            case .duration: "clock"
            }
        }
    }

    /// Rows in the chosen display order. `original` and `dateAdded` both use the
    /// service's native order (which for playlists/liked reflects when a track was
    /// added); the reverse toggle flips any of them.
    private var displayedTracks: [UnifiedTrack] {
        let base: [UnifiedTrack]
        switch sort {
        case .original, .dateAdded:
            base = tracks
        case .title:
            base = tracks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .artist:
            base = tracks.sorted { $0.artistNames.localizedCaseInsensitiveCompare($1.artistNames) == .orderedAscending }
        case .album:
            base = tracks.sorted { ($0.album ?? "").localizedCaseInsensitiveCompare($1.album ?? "") == .orderedAscending }
        case .duration:
            base = tracks.sorted { $0.durationMs < $1.durationMs }
        }
        return sortReversed ? base.reversed() : base
    }

    var body: some View {
        List {
            Section {
                // The hero is the first scrolling row (not a pinned section
                // header), so it scrolls away and the songs are fully readable.
                hero
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(theme.palette.rose)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 24)
                } else if tracks.isEmpty {
                    // A playlist Spotify says has tracks but that came back empty is a
                    // load failure (expired token / transient API error), not an empty
                    // playlist — offer a retry instead of lying with "Empty playlist".
                    VStack(spacing: 10) {
                        Text(playlistTracks.didFail(playlist) ? "Couldn't load tracks" : "Empty playlist")
                            .font(Typography.body(14))
                            .foregroundStyle(theme.palette.textSecondary)
                        if playlistTracks.didFail(playlist) {
                            Button { Task { await load(force: true) } } label: {
                                Text("Retry").font(Typography.semibold(14))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20).padding(.vertical, 9)
                                    .background(theme.palette.rose)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 24)
                } else {
                    songsHeader
                        .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 6, trailing: 18))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                        UnifiedTrackRow(track: track, rank: index + 1) {
                            Task { await player.play(track) }
                        }
                        .padding(.horizontal, 12)
                        .background(
                            theme.palette.card,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .stroke(theme.palette.border, lineWidth: 1)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        // While the hero (cover + name) is on screen the bar stays quiet; once
        // it scrolls under the bar, the name fades into the glass nav so the
        // back arrow never floats over bare content.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(playlist.name)
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                    .opacity(showBarTitle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.18), value: showBarTitle)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 300
        } action: { _, past in
            showBarTitle = past
        }
        .task(id: playlist.key) { await load() }
        .sheet(isPresented: $showingSortOptions) {
            HeartableChoiceSheet(
                title: "Sort tracks",
                items: TrackSort.allCases.map { option in
                    HeartableChoiceItem(
                        id: option.rawValue,
                        icon: option.icon,
                        title: option.rawValue,
                        isSelected: sort == option
                    )
                } + [
                    HeartableChoiceItem(
                        id: "reverse",
                        icon: "arrow.up.arrow.down",
                        title: "Reverse order",
                        isSelected: sortReversed
                    ),
                ],
                onCancel: { showingSortOptions = false },
                onSelect: { item in
                    if item.id == "reverse" {
                        sortReversed.toggle()
                    } else if let next = TrackSort(rawValue: item.id) {
                        sort = next
                    }
                    showingSortOptions = false
                }
            )
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            cover
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                .padding(.bottom, 16)

            Text(playlist.name)
                .font(Typography.heading(24))
                .foregroundStyle(theme.palette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let desc = playlist.description, !desc.isEmpty {
                Text(desc)
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.top, 6)
            }

            Text(metaLine)
                .font(Typography.semibold(12))
                .foregroundStyle(theme.palette.textMuted)
                .textCase(.uppercase)
                .padding(.top, 10)

            if !loading, !tracks.isEmpty {
                controls.padding(.top, 18)
            }

            if playlistTracks.isRefreshing(playlist), !tracks.isEmpty {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.palette.rose)
                    Text("Checking for updates")
                        .font(Typography.body(11))
                        .foregroundStyle(theme.palette.textMuted)
                }
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            theme.palette.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var songsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Songs")
                .font(Typography.semibold(12))
                .foregroundStyle(theme.palette.text)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            Text("\(tracks.count)")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tracks.count) songs")
    }

    private var cover: some View {
        CoverArt(
            url: playlist.image,
            corner: 24,
            placeholder: "music.note.list",
            placeholderScale: 0.22
        )
    }

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: prefs.mode.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.palette.textSecondary)
                Text(prefs.mode.label)
                    .font(Typography.semibold(13))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Spacer(minLength: 4)
            sortMenu
            Button(action: { Task { await playAll() } }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(theme.palette.rose))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play all")
        }
    }

    /// Display-sort affordance. Reorders only the visible rows; playback order is
    /// unchanged (still `prefs.mode`).
    private var sortMenu: some View {
        Button {
            showingSortOptions = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                Text(sort.short)
                    .font(Typography.semibold(13))
            }
            .foregroundStyle(theme.palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(theme.palette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort tracks")
        .accessibilityValue(sort.rawValue + (sortReversed ? ", reversed" : ""))
    }

    private var metaLine: String {
        let count = "\(tracks.count) track\(tracks.count == 1 ? "" : "s")"
        if let owner = playlist.owner, !owner.isEmpty {
            return "\(owner) · \(count)"
        }
        return count
    }

    private func load(force: Bool = false) async {
        await playlistTracks.load(playlist, force: force)
    }

    private func playAll() async {
        guard !tracks.isEmpty else { return }
        sortStore.recordPlayed(playlist.key)   // powers the Library "Recent" sort
        let ordered = prefs.order(tracks.map(\.uri))
        guard let firstURI = ordered.first,
              let first = tracks.first(where: { $0.uri == firstURI }) ?? tracks.first
        else { return }
        await player.play(first)
    }
}
