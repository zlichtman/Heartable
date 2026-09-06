import SwiftUI

struct RadioLibraryView: View {
    @Environment(ThemeStore.self) private var theme
    let saved: SavedRadioStations
    @State private var shows: [WSUMShow] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !saved.stations.isEmpty {
                    heading("Saved stations")
                    ForEach(saved.stations, id: \.id) { RadioStationRow(station: $0, saved: saved) }
                }
                let remaining = FeaturedRadioStations.all.filter { !saved.contains($0.id) }
                if !remaining.isEmpty {
                    heading("WSUM")
                    ForEach(remaining, id: \.id) {
                        RadioStationRow(station: $0, saved: saved)
                    }
                }
                heading("Shows")
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let upcoming = shows.filter { $0.endsAt > timeline.date }
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
        .navigationTitle("Radio")
        .navigationBarTitleDisplayMode(.inline)
        .task { shows = await WSUMShows.shared.load(); loading = false }
        .refreshable { shows = await WSUMShows.shared.load(force: true) }
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
                Image(systemName: saved.contains(station.id) ? "bookmark.fill" : "bookmark")
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
    let show: WSUMShow
    @State private var expanded = false

    var body: some View {
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
    }
}

private struct WSUMShowSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss
    let show: WSUMShow

    var body: some View {
        HeartableDrawer {
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
                Link(destination: show.pageURL) {
                    Label("Show details & playlists", systemImage: "arrow.up.right")
                        .font(Typography.semibold(14)).foregroundStyle(theme.palette.rose)
                        .frame(minHeight: 44)
                }
            }.padding(20)
        }
    }
}
