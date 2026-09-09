import SwiftUI

/// Library — the home tab. A universal search box spans songs, artists, playlists,
/// and people in one field. When the box is empty it's a browse view of the unified
/// library: a master "Liked Songs" list plus every playlist/folder/mixtape, with a
/// Playlists/Artists toggle. The header shows every live service (lit when connected)
/// and the profile access circle. Ported from the RN LibraryScreen.
struct LibraryView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(LibrarySortStore.self) private var sortStore
    @Environment(ProvidersStore.self) private var providers
    @Environment(PlaylistTracksRepository.self) private var playlistTracks
    @Environment(LibrarySessionStore.self) private var librarySession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Owned by AppTabView so re-tapping the Library tab pops back to root.
    @Binding var navPath: NavigationPath

    @State private var showCustomReorder = false
    @State private var showProviderReorder = false
    @State private var browseMode: BrowseMode = .playlists
    @State private var searchText = ""
    /// Long-lived, account-scoped stores owned above the tab hierarchy. A Home
    /// tab rebuild therefore cannot restart hydration or artist indexing.
    private var store: LibraryStore { librarySession.library }
    private var master: MasterLibraryStore { librarySession.master }

    // Existing folders remain readable; creation is hidden until the backend
    // workflow is reliable enough to ship.
    @State private var folders: [FolderDTO] = []

    enum BrowseMode: String, CaseIterable, Identifiable {
        case playlists = "Playlists", artists = "Artists"
        var id: String { rawValue }
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                headerBlock
                content
                    // Search placeholders have a short intrinsic height. Give the
                    // content region the remaining space and keep it top-aligned
                    // so keyboard presentation cannot recenter the whole page.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UnifiedPlaylist.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: LibraryStore.ArtistAgg.self) {
                ArtistDetailView(artist: $0, store: store)
            }
            .navigationDestination(for: SearchArtistRoute.self) { route in
                ArtistDetailView(
                    artist: route.artist,
                    store: store,
                    supplementalTracks: route.tracks
                )
            }
            .navigationDestination(for: FriendRef.self) { ref in
                FriendProfileView(
                    userId: ref.userId,
                    displayName: ref.displayName,
                    avatarUrl: ref.avatarUrl
                )
            }
            .task { await loadFolders() }
            // A single debounced, cancellable federated search owned by the store.
            .onChange(of: searchText) { _, text in
                master.setSearch(text, localPlaylists: store.playlists)
            }
            .refreshable {
                if !providers.hasRefreshed { await providers.refresh() }
                await loadLibrary(force: true)
                await loadFolders()
            }
            .sheet(isPresented: $showCustomReorder) {
                CustomOrderSheet(playlists: sortStore.sorted(store.playlists), sortStore: sortStore)
                    .environment(theme)
            }
            .sheet(isPresented: $showProviderReorder) {
                ProviderOrderSheet(present: presentProviders(), sortStore: sortStore)
                    .environment(theme)
            }
        }
    }

    private func loadLibrary(force: Bool) async {
        await librarySession.synchronize(
            providers: providers.connected,
            playlistTracks: playlistTracks,
            force: force
        )
    }

    /// Sources (in current priority order) that actually have playlists right now.
    /// Includes Heartable Mixtapes (`.heartable`) so it can be reordered like any other.
    private func presentProviders() -> [ProviderID] {
        let live = Set(store.playlists.map(\.providerID))
        return sortStore.providerOrder.filter { live.contains($0) }
    }

    // MARK: Header

    // In-content header (RN style): title + service status + profile, then search.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HeartablePageHeader(tab: .library)
                providerStatusRow
            }
            searchRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Round marks for the services you're actually connected to, directly under
    /// the title. Only connected services appear (unconnected ones are managed on
    /// the Music Services screen), so the row is a lit roster, not a status grid.
    @ViewBuilder
    private var providerStatusRow: some View {
        let ids = ProviderCatalog.all
            .filter { $0.section == .library && providers.isConnected($0.id) }
            .map(\.id)
        if !ids.isEmpty {
            HStack(spacing: 6) {
                ForEach(ids) { id in
                    ProviderBadge(id: id, size: 24, connected: true)
                }
            }
        }
    }

    /// The primary Library task is finding music. Broken creation affordances are
    /// intentionally absent until their end-to-end workflows are dependable.
    private var searchRow: some View {
        HStack(spacing: 10) {
            searchField
            NavigationLink {
                RadioLibraryView(saved: librarySession.savedRadio)
                    .navigationTitle("Radio")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                    .tint(theme.palette.rose)
            } label: {
                Image(systemName: "radio")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.palette.rose)
                    .frame(width: 44, height: 44)
                    .background(theme.palette.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Radio")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.palette.textMuted)
            TextField("", text: $searchText, prompt: Text("Songs, artists, playlists, people")
                .foregroundStyle(theme.palette.textMuted))
                .foregroundStyle(theme.palette.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.palette.textMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, searchText.isEmpty ? 12 : 2)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(theme.palette.surface)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            LibrarySearchResultsView(
                master: master,
                providerOrder: sortStore.providerOrder,
                connectedProviderIDs: providers.connected.map(\.id),
                localPlaylists: store.playlists
            )
        } else {
            browse
        }
    }

    // MARK: Browse

    private var browse: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                browseControls
                // Liked Songs is its own dedicated bar between the controls and
                // the playlists list (not a row inside the list).
                if browseMode == .playlists {
                    likedBar
                }
                if store.loading && store.playlists.isEmpty {
                    loadingRow
                } else if browseMode == .playlists {
                    playlistsBody
                } else {
                    artistsSection
                }
            }
            .padding(.top, 4)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Full-width tappable bar for the master Liked Songs list. Opens the same
    /// destination the old Liked entry used (LikedSongsView).
    private var likedBar: some View {
        NavigationLink { LikedSongsView(store: store) } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(LinearGradient(colors: [theme.palette.grad1, theme.palette.rose],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heartables")
                        .font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.text)
                    Text("\(store.likedTracks.count) song\(store.likedTracks.count == 1 ? "" : "s") · all services")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.palette.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.palette.card,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    /// Mode toggle on the left; sort + layout controls on the right (Playlists only).
    private var browseControls: some View {
        HStack(spacing: 10) {
            ForEach(BrowseMode.allCases) { mode in
                modeChip(mode)
            }
            Spacer(minLength: 0)
            if browseMode == .playlists {
                sortButton
                layoutButton
            } else if browseMode == .artists {
                artistSortButton
            }
        }
        .padding(.horizontal, 16)
    }

    private func modeChip(_ mode: BrowseMode) -> some View {
        let on = browseMode == mode
        return Button { browseMode = mode } label: {
            Text(mode.rawValue)
                .font(Typography.semibold(13))
                .foregroundStyle(on ? .white : theme.palette.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .frame(minHeight: 44)
                .background(on ? theme.palette.rose : theme.palette.surface)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Tap cycles the sort (A–Z → Recent → Creator → Custom); long-press opens the
    /// reorder sheet for the two manual modes.
    private var sortButton: some View {
        Button { sortStore.cycleSort() } label: {
            HStack(spacing: 6) {
                Image(systemName: sortStore.sortMode.icon).font(.system(size: 13, weight: .semibold))
                Text(sortStore.sortMode.label).font(Typography.semibold(13))
                if sortStore.sortMode.isReorderable {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                        .foregroundStyle(theme.palette.textMuted)
                }
            }
            .foregroundStyle(theme.palette.text)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                switch sortStore.sortMode {
                case .custom: showCustomReorder = true
                case .creator: showProviderReorder = true
                default: break
                }
            }
        )
    }

    private var layoutButton: some View {
        Button {
            sortStore.layout = sortStore.layout == .grid ? .list : .grid
        } label: {
            Image(systemName: sortStore.layout == .grid ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.palette.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sortStore.layout == .grid ? "Show as list" : "Show as grid")
    }

    private var artistSortButton: some View {
        Button { sortStore.cycleArtistSort() } label: {
            HStack(spacing: 6) {
                Image(systemName: sortStore.artistSortMode.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(sortStore.artistSortMode.label)
                    .font(Typography.semibold(13))
            }
            .foregroundStyle(theme.palette.text)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort artists")
        .accessibilityValue(sortStore.artistSortMode.label)
        .accessibilityHint("Switches between A to Z and song count")
    }

    @ViewBuilder
    private var playlistsBody: some View {
        if folders.isEmpty && store.playlists.isEmpty {
            emptyText("No playlists yet. Connect a music service to bring them into Heartable.")
        } else if sortStore.layout == .grid {
            gridLayout
        } else {
            listLayout
        }
    }

    private var sortedPlaylists: [UnifiedPlaylist] { sortStore.sorted(store.playlists) }

    private var gridLayout: some View {
        let minimumWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 150 : 112
        let columns = [GridItem(.adaptive(minimum: minimumWidth), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(folders) { folder in
                NavigationLink {
                    FolderDetailView(folder: folder) { Task { await loadFolders() } }
                } label: { folderTile(folder) }
                    .buttonStyle(.plain)
            }
            ForEach(sortedPlaylists) { pl in
                playlistNavLink(pl) { playlistCard(pl) }
            }
        }
        .padding(.horizontal, 16)
    }

    private var listLayout: some View {
        LazyVStack(spacing: 2) {
            ForEach(folders) { folder in
                NavigationLink {
                    FolderDetailView(folder: folder) { Task { await loadFolders() } }
                } label: {
                    folderRow(folder)
                }
                .buttonStyle(.plain)
            }
            ForEach(sortedPlaylists) { pl in
                playlistNavLink(pl) { playlistRow(pl) }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Existing mixtapes remain readable; provider playlists open their detail.
    @ViewBuilder
    private func playlistNavLink<Content: View>(_ pl: UnifiedPlaylist,
                                                @ViewBuilder content: () -> Content) -> some View {
        if pl.isMixtape, let uuid = UUID(uuidString: pl.playlistID) {
            NavigationLink { MixtapeEditorView(mixtapeID: uuid) } label: { content() }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: pl) { content() }
                .buttonStyle(.plain)
        }
    }

    private func folderTile(_ folder: FolderDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                theme.palette.surface
                Image(systemName: "folder.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(theme.palette.rose)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            Text(folder.name).font(Typography.semibold(14))
                .foregroundStyle(theme.palette.text).lineLimit(1)
            Text("\(folder.itemCount) playlist\(folder.itemCount == 1 ? "" : "s")")
                .font(Typography.body(11))
                .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
        }
    }

    private func folderRow(_ folder: FolderDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                theme.palette.surface
                Image(systemName: "folder.fill").font(.system(size: 20))
                    .foregroundStyle(theme.palette.rose)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text).lineLimit(1)
                Text("Folder · \(folder.itemCount) playlist\(folder.itemCount == 1 ? "" : "s")")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func playlistRow(_ pl: UnifiedPlaylist) -> some View {
        HStack(spacing: 12) {
            CoverArt(url: pl.image, size: 52,
                     placeholder: pl.isMixtape ? "rectangle.stack.badge.play" : "music.note.list")
            VStack(alignment: .leading, spacing: 2) {
                Text(pl.name).font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text).lineLimit(1)
                Text(playlistSubtitle(pl)).font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var sortedArtists: [LibraryStore.ArtistAgg] {
        store.sortedArtists(sortStore.artistSortMode)
    }

    private var artistsSection: some View {
        Group {
            if store.indexingArtists && store.artists.isEmpty {
                loadingRow
            } else if store.artists.isEmpty {
                emptyText("No artists yet")
            } else {
                LazyVStack(spacing: 0) {
                    // Still indexing: show a slim hint that more artists are loading
                    // (liked + top already show; playlists are filling in).
                    if store.indexingArtists {
                        HStack(spacing: 8) {
                            ProgressView().tint(theme.palette.rose)
                            Text("Scanning playlists…")
                                .font(Typography.body(12))
                                .foregroundStyle(theme.palette.textSecondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    ForEach(sortedArtists) { artist in
                        NavigationLink(value: artist) {
                            ArtistRow(artist: artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        // Build the full library-wide index the first time the Artists tab shows.
        .task(id: browseMode) {
            if browseMode == .artists {
                await store.loadArtistIndex(using: playlistTracks)
            }
        }
    }

    // MARK: Rows / cards

    private func playlistCard(_ pl: UnifiedPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(url: pl.image, corner: Theme.Radius.md,
                     placeholder: pl.isMixtape ? "rectangle.stack.badge.play" : "music.note.list")

            Text(pl.name).font(Typography.semibold(14))
                .foregroundStyle(theme.palette.text).lineLimit(1)
            Text(playlistSubtitle(pl))
                .font(Typography.body(11))
                .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
        }
    }

    /// Spotify-style second line: "Mixtape · {owner}" for Heartable tapes, otherwise
    /// "Playlist · {owner}" (or track count when known).
    private func playlistSubtitle(_ pl: UnifiedPlaylist) -> String {
        if pl.isMixtape { return pl.owner ?? "Mixtape" }
        if let owner = pl.owner, !owner.isEmpty { return "Playlist · \(owner)" }
        if pl.trackCount > 0 { return "Playlist · \(pl.trackCount) tracks" }
        return "Playlist"
    }

    // MARK: Bits

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView().tint(theme.palette.rose)
            Spacer()
        }
        .padding(.top, 40)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(Typography.body(14))
            .foregroundStyle(theme.palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    // MARK: Data

    private func loadFolders() async {
        folders = await BackendAPI.shared.listFolders()
    }

}

// MARK: - Artist row

private struct ArtistRow: View {
    @Environment(ThemeStore.self) private var theme
    let artist: LibraryStore.ArtistAgg

    var body: some View {
        HStack(spacing: 12) {
            ArtistAvatar(url: artist.artURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name).font(Typography.semibold(14))
                    .foregroundStyle(theme.palette.text).lineLimit(1)
                Text(meta).font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(Array(artist.providers), id: \.self) { pid in
                    ProviderBadge(id: pid, size: 16)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var meta: String {
        let songs = "\(artist.count) song\(artist.count == 1 ? "" : "s")"
        let services = artist.providers.count
        return services > 1 ? "\(songs) · \(services) services" : songs
    }
}

// MARK: - Reorder sheets

/// Drag to set the manual playlist order used by the Custom sort. New playlists
/// always land on top; this just rearranges everything already known.
private struct CustomOrderSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State var playlists: [UnifiedPlaylist]
    let sortStore: LibrarySortStore

    var body: some View {
        HeartableReorderSheet(title: "Custom order", items: playlists, onMove: { from, to in
            playlists.move(fromOffsets: from, toOffset: to)
            sortStore.setCustomOrder(playlists.map(\.key))
        }) { playlist in
            HStack(spacing: 12) {
                CoverArt(url: playlist.image, size: 40, corner: 8, placeholder: "music.note.list")
                Text(playlist.name)
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(2)
            }
        }
    }
}

/// Drag to set creator priority for the Creator sort. Heartable Mixtapes is just
/// another entry here (no forced first position) and can be moved anywhere.
private struct ProviderOrderSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State var present: [ProviderID]
    let sortStore: LibrarySortStore

    var body: some View {
        HeartableReorderSheet(title: "Creator priority", items: present, onMove: { from, to in
            present.move(fromOffsets: from, toOffset: to)
            commit()
        }) { id in
            HStack(spacing: 12) {
                ProviderBadge(id: id, size: 26)
                Text(label(id))
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(2)
            }
        }
    }

    private func label(_ id: ProviderID) -> String {
        id == .heartable ? "Heartable Mixtapes" : (ProviderCatalog.entry(id)?.label ?? id.rawValue)
    }

    /// Reordered present providers first, then any others (absent right now) kept
    /// in their prior relative order so the full priority list stays complete.
    private func commit() {
        let rest = sortStore.providerOrder.filter { !present.contains($0) }
        sortStore.setProviderOrder(present + rest)
    }
}
