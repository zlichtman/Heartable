import SwiftUI

struct RadioLibraryView: View {
    @Environment(ThemeStore.self) private var theme
    let saved: SavedRadioStations
    var query: String = ""
    @State private var stationQuery = ""

    private var searchTerm: String { query.isEmpty ? stationQuery : query }
    private var matches: [FeaturedRadioStations.Station] {
        searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? FeaturedRadioStations.all : FeaturedRadioStations.matching(searchTerm)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !matches.filter({ saved.contains($0.id) }).isEmpty {
                    heading("Saved stations")
                    ForEach(matches.filter { saved.contains($0.id) }, id: \.id) { RadioStationRow(station: $0, saved: saved) }
                }
                let remaining = matches.filter { !saved.contains($0.id) }
                if !remaining.isEmpty {
                    heading("Stations")
                    ForEach(remaining, id: \.id) {
                        RadioStationRow(station: $0, saved: saved)
                    }
                }
                if matches.isEmpty {
                    Text("No stations found").font(Typography.body(14))
                        .foregroundStyle(theme.palette.textMuted)
                }
            }.padding(20)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .searchable(text: $stationQuery, prompt: "Search stations")
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
                    if station.providerID == .wsum {
                        ProviderLogo(id: .wsum, size: 48)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 24)).foregroundStyle(theme.palette.rose)
                            .frame(width: 48, height: 48)
                            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 11))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.name).font(Typography.semibold(15)).foregroundStyle(theme.palette.text)
                        Text(station.location).font(Typography.body(12)).foregroundStyle(theme.palette.textSecondary)
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
