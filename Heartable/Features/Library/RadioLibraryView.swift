import SwiftUI

struct RadioLibraryView: View {
    @Environment(ThemeStore.self) private var theme
    let saved: SavedRadioStations
    var query: String = ""
    @State private var shows: [WSUMShow] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !saved.stations.filter({ query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }).isEmpty {
                    heading("Saved stations")
                    ForEach(saved.stations.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }, id: \.id) { RadioStationRow(station: $0, saved: saved) }
                }
                let remaining = FeaturedRadioStations.all.filter { !saved.contains($0.id) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
                if !remaining.isEmpty {
                    heading("WSUM")
                    ForEach(remaining, id: \.id) {
                        RadioStationRow(station: $0, saved: saved)
                    }
                }
                heading("Shows")
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let upcoming = radioShows(at: timeline.date)
                    VStack(alignment: .leading, spacing: 16) {
                        if upcoming.isEmpty {
                            Text(loading ? "Loading schedule…" : "The schedule is unavailable. Live stations still work.")
                                .font(Typography.body(14)).foregroundStyle(theme.palette.textMuted)
                        }
                        ForEach(upcoming) { WSUMShowRow(show: $0) }
                    }
                }
            }.padding(20)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .task { shows = await WSUMShows.shared.load(); loading = false }
        .refreshable { shows = await WSUMShows.shared.load(force: true) }
    }

    private func radioShows(at date: Date) -> [WSUMShow] {
        var seen = Set<String>()
        return shows.filter {
            $0.endsAt > date && (query.isEmpty || $0.matches(query)) && seen.insert($0.favoriteID).inserted
        }.sorted {
            let a = saved.contains($0.favoriteID), b = saved.contains($1.favoriteID)
            return a != b ? a : $0.startsAt < $1.startsAt
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(Typography.heading(22)).foregroundStyle(theme.palette.text)
    }
}

struct RadioStationRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    let station: FeaturedRadioStations.Station
    let saved: SavedRadioStations

    var body: some View {
        HStack(spacing: 12) {
            Button { Task { await player.play(station.track) } } label: {
                HStack(spacing: 12) {
                    ProviderLogo(id: .wsum, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.name).font(Typography.semibold(15)).foregroundStyle(theme.palette.text)
                        Text("Live radio").font(Typography.body(12)).foregroundStyle(theme.palette.textSecondary)
                    }
                    Spacer(minLength: 4)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(station.name)")
            Button { saved.toggle(station.id) } label: {
                Image(systemName: saved.contains(station.id) ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.palette.rose)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved.contains(station.id) ? "Unsave \(station.name)" : "Save \(station.name)")
            .accessibilityIdentifier("radio.save.\(station.id)")
        }.padding(.vertical, 6)
    }
}

struct WSUMShowRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(LibrarySessionStore.self) private var librarySession
    let show: WSUMShow
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 8) {
        Button { expanded = true } label: {
            HStack(spacing: 12) {
                Image(systemName: show.isOnAir() ? "waveform" : "calendar")
                    .foregroundStyle(theme.palette.rose).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title).font(Typography.semibold(15)).foregroundStyle(theme.palette.text)
                    Text(show.host).font(Typography.body(12)).foregroundStyle(theme.palette.textSecondary)
                    Text(show.isOnAir() ? "On air now · WSUM 91.7 FM" : show.airtime)
                        .font(Typography.medium(11)).foregroundStyle(theme.palette.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.textMuted)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $expanded) { WSUMShowSheet(show: show) }
            Button { librarySession.savedRadio.toggle(show.favoriteID) } label: {
                Image(systemName: librarySession.savedRadio.contains(show.favoriteID) ? "heart.fill" : "heart")
                    .foregroundStyle(theme.palette.rose).frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel("Favorite \(show.title)")
        }
    }
}

private struct WSUMShowSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss
    let show: WSUMShow
    @State private var broadcasts: [WSUMBroadcast] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(show.title).font(Typography.heading(26)).foregroundStyle(theme.palette.text)
                Text(show.host).font(Typography.body(16)).foregroundStyle(theme.palette.textSecondary)
                Text(show.airtime).font(Typography.medium(13)).foregroundStyle(theme.palette.textMuted)
                if show.isOnAir(), let station = FeaturedRadioStations.station(id: "wsum-fm") {
                    Button {
                        // A sheet may remain open across a broadcast boundary.
                        // Never imply that the next show's stream is this show.
                        if show.isOnAir() { Task { await player.play(station.track) } }
                        dismiss()
                    } label: {
                        Label("Listen live", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(theme.palette.bg)
                            .background(theme.palette.rose, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Text("Recent broadcasts").font(Typography.heading(21)).foregroundStyle(theme.palette.text)
                if loading { ProgressView().tint(theme.palette.rose) }
                if failed {
                    Button("Couldn't load broadcasts. Retry") { Task { await load() } }
                        .foregroundStyle(theme.palette.rose).frame(minHeight: 44)
                } else if !loading && broadcasts.isEmpty {
                    Text("No published playlists yet.").foregroundStyle(theme.palette.textMuted)
                }
                ForEach(broadcasts) { broadcast in
                    NavigationLink { WSUMBroadcastView(broadcast: broadcast) } label: {
                        HStack {
                            Text(broadcast.title).font(Typography.semibold(14))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.foregroundStyle(theme.palette.text).padding(14)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }.padding(20)
            }.background(theme.palette.bg)
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .tint(theme.palette.rose)
        .heartableSheetChrome()
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            if show.pageURL.path.contains("/pl/") {
                broadcasts = [.init(id: show.id, title: show.airtime, url: show.pageURL)]
            } else {
                broadcasts = try WSUMArchive.broadcasts(await WSUMArchive.shared.page(show.pageURL))
            }
        } catch { failed = true }
        loading = false
    }
}

private struct WSUMBroadcastView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(LibrarySessionStore.self) private var librarySession
    @Environment(ProvidersStore.self) private var providers
    let broadcast: WSUMBroadcast
    @State private var tracks: [WSUMSpin] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(broadcast.title).font(Typography.heading(23))
                Text("WSUM · Broadcast playlist").font(Typography.body(12)).foregroundStyle(theme.palette.textMuted)
                if loading { ProgressView().tint(theme.palette.rose) }
                if failed {
                    Button("Couldn't load tracks. Retry") { Task { await load() } }.frame(minHeight: 44)
                } else if !loading && tracks.isEmpty {
                    Text("No tracks were logged for this broadcast.")
                }
                ForEach(tracks) { track in
                    RadioRecordingRow(spin: track, cached: cachedMatches[track.id])
                }
            }.foregroundStyle(theme.palette.text).padding(20)
        }.background(theme.palette.bg).navigationTitle("Playlist").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @State private var cachedMatches: [String: UnifiedTrack] = [:]

    private func load() async {
        failed = false
        do { tracks = try WSUMArchive.spins(await WSUMArchive.shared.page(broadcast.url)) }
        catch { failed = true }
        loading = false
        let spins = tracks
        let connected = providers.connectedIDs
        let candidates = librarySession.master.tracks.flatMap(\.sources).filter { connected.contains($0.providerID) }
        let owner = AccountSessionStore.currentOwnerID
        let matches = await Task.detached(priority: .utility) {
            let byTitle = Dictionary(grouping: candidates) { RadioRecordingMatcher.normalized($0.name) }
            return Dictionary(uniqueKeysWithValues: spins.compactMap { spin -> (String, UnifiedTrack)? in
                guard let match = RadioRecordingMatcher.match(spin, in: byTitle[RadioRecordingMatcher.normalized(spin.song)] ?? []) else { return nil }
                return (spin.id, match)
            })
        }.value
        guard !Task.isCancelled, owner == AccountSessionStore.currentOwnerID else { return }
        cachedMatches = matches
        // Resolve the whole short broadcast, not just lazily mounted rows.
        // One request at a time avoids a burst when the playlist opens; Spotify's
        // shared read backoff also honors Retry-After without hiding cached rows.
        for spin in spins where cachedMatches[spin.id] == nil {
            guard !Task.isCancelled, owner == AccountSessionStore.currentOwnerID else { return }
            if let cached = RadioRecordingCache.shared.match(spin, connected: Set(providers.connectedIDs)) {
                cachedMatches[spin.id] = cached
                continue
            }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            for id in [ProviderID.apple, .spotify, .plex, .jellyfin] where providers.connectedIDs.contains(id) {
                guard !Task.isCancelled, owner == AccountSessionStore.currentOwnerID else { return }
                let results = await ProviderRegistry.provider(for: id).search("\(spin.song) \(spin.artist)")
                guard !Task.isCancelled, owner == AccountSessionStore.currentOwnerID else { return }
                if let found = RadioRecordingMatcher.match(spin, in: results), providers.connectedIDs.contains(id) {
                    cachedMatches[spin.id] = found
                    RadioRecordingCache.shared.store(found, for: spin)
                    break
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }
}

private struct RadioRecordingRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(ProvidersStore.self) private var providers
    @Environment(PlayerStore.self) private var player
    let spin: WSUMSpin
    let cached: UnifiedTrack?
    @State private var resolved: UnifiedTrack?
    @State private var request = 0
    @State private var searching = false
    @State private var unavailable = false

    private var match: UnifiedTrack? {
        guard let track = resolved ?? cached, providers.connectedIDs.contains(track.providerID) else { return nil }
        return track
    }

    var body: some View {
        Button {
            if let match { Task { await player.play(match) } }
            else { request += 1 }
        } label: {
            HStack(spacing: 12) {
                CoverArt(url: match?.albumArt, size: 52, corner: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(spin.song).font(Typography.semibold(15)).foregroundStyle(theme.palette.text)
                    Text(spin.artist).font(Typography.body(13)).foregroundStyle(theme.palette.textSecondary)
                    Text(searching ? "Finding song…" : match != nil ? "\(spin.time) · \(ProviderCatalog.entry(match!.providerID)?.label ?? "")" : unavailable ? "No exact match · Tap to retry" : "\(spin.time) · Find song")
                        .font(Typography.body(11)).foregroundStyle(theme.palette.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: match == nil ? "magnifyingglass" : "play.fill")
                    .foregroundStyle(theme.palette.rose)
            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(searching)
        .task(id: request) {
            guard request > 0 else { return }
            searching = true
            defer { searching = false }
            let owner = AccountSessionStore.currentOwnerID
            for id in [ProviderID.spotify, .apple, .plex, .jellyfin] where providers.connectedIDs.contains(id) {
                let candidates = await ProviderRegistry.provider(for: id).search("\(spin.song) \(spin.artist)")
                guard !Task.isCancelled, owner == AccountSessionStore.currentOwnerID else { return }
                if let found = RadioRecordingMatcher.match(spin, in: candidates), providers.connectedIDs.contains(id) {
                    resolved = found
                    RadioRecordingCache.shared.store(found, for: spin)
                    unavailable = false
                    return
                }
            }
            unavailable = true
        }
    }
}
