import SwiftUI

enum LibrarySearchResultType: String, CaseIterable, Identifiable {
    case all = "All"
    case songs = "Songs"
    case artists = "Artists"
    case radio = "Radio"
    case profiles = "Profiles"
    case playlists = "Playlists"

    var id: String { rawValue }
}

struct SearchArtistRoute: Hashable {
    let artist: LibraryStore.ArtistAgg
    let tracks: [UnifiedTrack]
}

/// The unified search surface: one query fanned out across every connected service
/// by `MasterLibraryStore`, rendered as merged, de-duplicated, source-tagged
/// results. Songs collapse across services into one row that remembers every
/// owning provider, so a tap plays from the best source and the menu offers the
/// others.
///
/// Visual stability: cached matches publish first, federated matches refine them
/// in one update, every `ForEach` uses stable identity, and a thin indicator
/// communicates refinement without making rows thrash provider by provider.
struct LibrarySearchResultsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(LibrarySessionStore.self) private var librarySession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let master: MasterLibraryStore
    /// User provider priority (from LibrarySortStore) for best-source routing.
    let providerOrder: [ProviderID]
    let connectedProviderIDs: [ProviderID]
    let localPlaylists: [UnifiedPlaylist]

    @State private var selectedType: LibrarySearchResultType = .all
    @State private var showingProviderPicker = false

    private var results: MasterLibraryStore.SearchResults { master.searchResults }
    private var selectedProviders: Set<ProviderID> {
        master.searchScope.resolved(connected: Set(connectedProviderIDs))
    }
    private var providerProjectedTracks: [MasterTrack] {
        // Project sources inside each already-ranked result. Regrouping the
        // entire list through a dictionary would scramble relevance on every tap.
        results.tracks.compactMap { track in
            let sources = track.sources.filter { selectedProviders.contains($0.providerID) }
            return sources.isEmpty ? nil : MasterTrack(identity: track.identity, sources: sources)
        }
    }
    private var tracks: [MasterTrack] {
        guard selectedType == .all || selectedType == .songs else { return [] }
        return providerProjectedTracks
    }
    private var artists: [MasterArtist] {
        guard selectedType == .all || selectedType == .artists else { return [] }
        return MasterLibraryStore.rankArtists(providerProjectedTracks, query: master.searchTerm)
    }
    private var playlists: [UnifiedPlaylist] {
        guard selectedType == .all || selectedType == .playlists else { return [] }
        return results.playlists.filter { selectedProviders.contains($0.providerID) }
    }
    private var profiles: [FoundProfileDTO] {
        guard selectedType == .all || selectedType == .profiles,
              selectedProviders.contains(.heartable) else { return [] }
        return results.people
    }
    private var sourceLabel: String {
        if master.searchScope.selection == nil { return "Libraries" }
        if selectedProviders.count == 1, let id = selectedProviders.first { return providerName(id) }
        return "\(selectedProviders.count) apps"
    }
    private var filteredIsEmpty: Bool {
        tracks.isEmpty && artists.isEmpty && playlists.isEmpty && profiles.isEmpty && shows.isEmpty
    }
    private var shows: [WSUMShow] {
        (selectedType == .all || selectedType == .radio) && selectedProviders.contains(.wsum) ? results.shows : []
    }
    private var visibleTracks: [MasterTrack] {
        selectedType == .all ? Array(tracks.prefix(8)) : tracks
    }
    private var visibleArtists: [MasterArtist] {
        selectedType == .all ? Array(artists.prefix(5)) : artists
    }
    private var visiblePlaylists: [UnifiedPlaylist] {
        selectedType == .all ? Array(playlists.prefix(5)) : playlists
    }
    private var visibleProfiles: [FoundProfileDTO] {
        selectedType == .all ? Array(profiles.prefix(5)) : profiles
    }
    private var filterProviders: [ProviderID] {
        var seen: Set<ProviderID> = [.heartable]
        return [.heartable] + (connectedProviderIDs + ProviderCatalog.publicSearchIDs)
            .filter { seen.insert($0).inserted }
    }
    private var filterColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 8),
            count: count
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Group {
                if selectedType == .radio {
                    RadioLibraryView(saved: librarySession.savedRadio, query: master.searchTerm)
                } else if master.searching && filteredIsEmpty {
                    loading
                } else if filteredIsEmpty {
                    empty
                } else {
                    list
                }
            }
        }
        .onChange(of: selectedProviders) {
            master.setSearch(master.searchTerm, localPlaylists: localPlaylists)
        }
        .sheet(isPresented: $showingProviderPicker) {
            SearchSourcesDrawer(
                items: providerFilterItems,
                onSelect: { item in
                    guard let id = ProviderID(rawValue: item.id) else { return }
                    master.searchScope.toggle(id, connected: Set(connectedProviderIDs))
                }
            )
        }
    }

    private var filterBar: some View {
        LazyVGrid(columns: filterColumns, spacing: 8) {
            ForEach(LibrarySearchResultType.allCases) { type in
                typeChip(type)
            }

            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                showingProviderPicker = true
            } label: {
                HStack(spacing: 6) {
                    if selectedProviders.count == 1, let id = selectedProviders.first {
                        ProviderLogo(id: id, size: 17)
                    }
                    Text(sourceLabel)
                        .font(Typography.semibold(12))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(theme.palette.text)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(theme.palette.surface, in: Capsule())
                .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter by app")
            .accessibilityValue(filterProviders.filter { selectedProviders.contains($0) }.map(providerName).joined(separator: ", "))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var providerFilterItems: [HeartableChoiceItem] {
        filterProviders.map { provider in
            HeartableChoiceItem(
                id: provider.rawValue,
                icon: "music.note",
                title: providerName(provider),
                isSelected: selectedProviders.contains(provider),
                providerID: provider
            )
        }
    }

    private func typeChip(_ type: LibrarySearchResultType) -> some View {
        let selected = selectedType == type
        return Button {
            selectedType = type
        } label: {
            Text(type.rawValue)
                .font(Typography.semibold(12))
                .foregroundStyle(selected ? .white : theme.palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
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
    }

    private func providerName(_ provider: ProviderID) -> String {
        if provider == .heartable { return "Heartable" }
        return ProviderCatalog.entry(provider)?.label ?? provider.rawValue
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Thin refinement bar: keeps the list mounted (no swap) while a
                // slower service is still being folded in.
                if master.searching {
                    HStack(spacing: 8) {
                        ProgressView().tint(theme.palette.rose)
                        Text("Searching your services")
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                if !tracks.isEmpty {
                    sectionHeader("Songs", count: tracks.count, type: .songs, shown: visibleTracks.count)
                    ForEach(visibleTracks) { track in
                        if let source = track.source(for: .wsum),
                           let station = FeaturedRadioStations.station(id: source.providerTrackID) {
                            RadioStationRow(station: station, saved: librarySession.savedRadio)
                        } else {
                            MasterTrackRow(
                            track: track,
                            providerOrder: providerOrder,
                            preferredProvider: selectedProviders.count == 1 ? selectedProviders.first : nil
                        )
                        }
                    }
                }
                if !shows.isEmpty {
                    Text("Shows").font(Typography.semibold(13)).foregroundStyle(theme.palette.textMuted)
                        .padding(.top, 20).padding(.bottom, 12)
                    ForEach(shows.prefix(20)) { WSUMShowRow(show: $0).padding(.vertical, 8) }
                }
                if !artists.isEmpty {
                    sectionHeader(
                        "Artists",
                        count: artists.count,
                        type: .artists,
                        shown: visibleArtists.count
                    )
                    ForEach(visibleArtists) { artist in
                        NavigationLink(value: artistRoute(artist)) {
                            MasterArtistRow(artist: artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !playlists.isEmpty {
                    sectionHeader(
                        "Playlists",
                        count: playlists.count,
                        type: .playlists,
                        shown: visiblePlaylists.count
                    )
                    ForEach(visiblePlaylists) { playlist in
                        NavigationLink(value: playlist) {
                            SearchPlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !profiles.isEmpty {
                    sectionHeader(
                        "Profiles",
                        count: profiles.count,
                        type: .profiles,
                        shown: visibleProfiles.count
                    )
                    ForEach(visibleProfiles) { person in
                        NavigationLink(
                            value: FriendRef(
                                userId: person.id,
                                displayName: person.displayName,
                                avatarUrl: person.avatarUrl
                            )
                        ) {
                            SearchPersonRow(person: person)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .animation(.default, value: results.tracks)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var loading: some View {
        HStack {
            Spacer()
            ProgressView().tint(theme.palette.rose)
            Spacer()
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private var empty: some View {
        if selectedProviders.isEmpty {
            emptyText("Choose an app in Search in.")
        } else if master.searchedWithNoProviders && selectedType != .profiles {
            emptyText("No matches. Add a search source or connect a music service.")
        } else {
            emptyText("No matches")
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(Typography.body(14))
            .foregroundStyle(theme.palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 40)
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        type: LibrarySearchResultType,
        shown: Int
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Typography.semibold(11))
                .foregroundStyle(theme.palette.textMuted)
                .textCase(.uppercase)
                .kerning(1)
            Text("\(count)")
                .font(Typography.medium(10))
                .foregroundStyle(theme.palette.textMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.palette.surface, in: Capsule())
            Spacer(minLength: 8)
            if selectedType == .all, count > shown {
                Button("See all") {
                    selectedType = type
                }
                .font(Typography.semibold(12))
                .foregroundStyle(theme.palette.rose)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// Reuse the existing artist-detail destination registered by LibraryView.
    private func artistAgg(_ artist: MasterArtist) -> LibraryStore.ArtistAgg {
        LibraryStore.ArtistAgg(
            name: artist.name,
            count: artist.count,
            providers: artist.providers,
            artURL: artist.artURL,
            spotifyArtistID: nil
        )
    }

    private func artistRoute(_ artist: MasterArtist) -> SearchArtistRoute {
        let artistKey = UnifiedTrackIdentity.normalizeArtist(artist.name)
        let sources = providerProjectedTracks
            .compactMap { master -> UnifiedTrack? in
                return master.bestPlaybackSource(order: providerOrder) ?? master.display
            }
            .filter { track in
                track.artists.contains {
                    UnifiedTrackIdentity.normalizeArtist($0.name) == artistKey
                }
            }
        return SearchArtistRoute(artist: artistAgg(artist), tracks: sources)
    }
}

// MARK: - Master track row (source-tagged, source picker)

/// One deduped song. Artwork + title + primary artist, a row of provider badges
/// for every service that serves it, with source and weighting actions available
/// on long press so the default row remains visually quiet.
/// Tapping the row plays from the best available source.
struct MasterTrackRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs
    let track: MasterTrack
    let providerOrder: [ProviderID]
    var preferredProvider: ProviderID? = nil
    @State private var showingActions = false

    private var best: UnifiedTrack? {
        if let preferredProvider,
           let preferred = track.source(for: preferredProvider),
           ProviderPlayback.isPlayable(preferred.providerID) {
            return preferred
        }
        return track.bestPlaybackSource(order: providerOrder)
    }

    var body: some View {
        Button {
            if let best { Task { await player.play(best) } }
        } label: {
            HStack(spacing: 12) {
                CoverArt(url: track.albumArt, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(Typography.semibold(15))
                        .foregroundStyle(track.isPlayable ? theme.palette.text : theme.palette.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(track.artistNames)
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(1)
                        badges
                    }
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .opacity(track.isPlayable ? 1 : 0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!track.isPlayable)
        .onLongPressGesture(minimumDuration: 0.4) {
            showingActions = true
        }
        .sheet(isPresented: $showingActions) {
            HeartableChoiceSheet(
                title: track.title,
                subtitle: "Choose a source or adjust Weighted mode.",
                items: actionItems,
                onCancel: { showingActions = false },
                onSelect: performAction
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.title)
        .accessibilityValue("\(track.artistNames), \(providerNames)")
        .accessibilityHint(
            track.isPlayable
                ? "Plays track. More actions available"
                : "No connected playback source"
        )
        .accessibilityActions {
            accessibilityTrackActions
        }
        .padding(.vertical, 6)
    }

    private var providerNames: String {
        track.providers
            .map { ProviderCatalog.entry($0)?.label ?? $0.rawValue }
            .joined(separator: ", ")
    }

    private var actionItems: [HeartableChoiceItem] {
        let sources = track.playableSources(order: providerOrder)
        var items = sources.count > 1
            ? sources.map { source in
                HeartableChoiceItem(
                    id: "play:\(source.providerID.rawValue)",
                    icon: "play.fill",
                    title: "Play from \(sourceLabel(source.providerID))",
                    isSelected: best?.providerID == source.providerID
                )
            }
            : []
        if let best {
            items.append(
                HeartableChoiceItem(
                    id: "boost",
                    icon: "arrow.up",
                    title: "Boost in shuffle"
                )
            )
            items.append(
                HeartableChoiceItem(
                    id: "downvote",
                    icon: "arrow.down",
                    title: "Downvote in shuffle"
                )
            )
            items.append(
                HeartableChoiceItem(
                    id: "reset",
                    icon: "arrow.counterclockwise",
                    title: "Reset shuffle weight",
                    isDisabled: prefs.weight(for: best.uri) == 0
                )
            )
        }
        return items
    }

    private func performAction(_ item: HeartableChoiceItem) {
        defer { showingActions = false }
        if item.id.hasPrefix("play:") {
            let raw = String(item.id.dropFirst("play:".count))
            guard let providerID = ProviderID(rawValue: raw),
                  let source = track.source(for: providerID) else { return }
            Task { await player.play(source) }
            return
        }
        guard let best else { return }
        switch item.id {
        case "boost": prefs.bump(best.uri, by: 10)
        case "downvote": prefs.bump(best.uri, by: -10)
        case "reset": prefs.setWeight(best.uri, to: 0)
        default: break
        }
    }

    /// One badge per owning service, in provenance order.
    private var badges: some View {
        HStack(spacing: 3) {
            ForEach(track.providers, id: \.self) { provider in
                ProviderBadge(id: provider, size: 15)
            }
        }
    }

    @ViewBuilder
    private var trackActions: some View {
        let sources = track.playableSources(order: providerOrder)
        if sources.count > 1 {
            Section("Play from") {
                ForEach(sources, id: \.key) { source in
                    Button {
                        Task { await player.play(source) }
                    } label: {
                        Label(sourceLabel(source.providerID), systemImage: "play.fill")
                    }
                }
            }
        }
        if let best {
            Button {
                prefs.bump(best.uri, by: 10)
            } label: {
                Label("Boost in shuffle", systemImage: "arrow.up")
            }
            Button {
                prefs.bump(best.uri, by: -10)
            } label: {
                Label("Downvote in shuffle", systemImage: "arrow.down")
            }
            if prefs.weight(for: best.uri) != 0 {
                Button {
                    prefs.setWeight(best.uri, to: 0)
                } label: {
                    Label("Reset shuffle weight", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    @ViewBuilder
    private var accessibilityTrackActions: some View {
        let sources = track.playableSources(order: providerOrder)
        if sources.count > 1 {
            ForEach(sources, id: \.key) { source in
                Button("Play from \(sourceLabel(source.providerID))") {
                    Task { await player.play(source) }
                }
            }
        }
        if let best {
            Button("Boost in shuffle") {
                prefs.bump(best.uri, by: 10)
            }
            Button("Downvote in shuffle") {
                prefs.bump(best.uri, by: -10)
            }
            if prefs.weight(for: best.uri) != 0 {
                Button("Reset shuffle weight") {
                    prefs.setWeight(best.uri, to: 0)
                }
            }
        }
    }

    private func sourceLabel(_ id: ProviderID) -> String {
        let name = ProviderCatalog.entry(id)?.label ?? id.rawValue
        return "\(name) · \(ProviderPlayback.label(for: id))"
    }
}

// MARK: - Supporting rows

private struct MasterArtistRow: View {
    @Environment(ThemeStore.self) private var theme
    let artist: MasterArtist

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
                ForEach(Array(artist.providers), id: \.self) { ProviderBadge(id: $0, size: 16) }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var meta: String {
        let songs = "\(artist.count) song\(artist.count == 1 ? "" : "s")"
        let services = artist.providers.count
        return services > 1 ? "\(songs) · \(services) services" : songs
    }
}

private struct SearchPlaylistRow: View {
    @Environment(ThemeStore.self) private var theme
    let playlist: UnifiedPlaylist

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(url: playlist.image, size: 46, placeholder: "music.note.list")
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(Typography.semibold(14))
                    .foregroundStyle(theme.palette.text).lineLimit(1)
                Text(playlist.trackCount > 0 ? "\(playlist.trackCount) tracks" : "View tracks")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct SearchPersonRow: View {
    @Environment(ThemeStore.self) private var theme
    let person: FoundProfileDTO

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(
                urlString: person.avatarUrl,
                name: person.displayName,
                size: 44
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName ?? "Listener")
                    .font(Typography.semibold(14))
                    .foregroundStyle(theme.palette.text).lineLimit(1)
                Text("on Heartable").font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
