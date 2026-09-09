import SwiftUI

/// Every track by one artist found anywhere in the library, grouped by where it
/// lives: a "Liked & Top" section for tracks with no playlist attribution, then a
/// section per playlist the artist appears in. Tapping a track plays it through
/// the environment PlayerStore, exactly like UnifiedTrackRow elsewhere. Reads from
/// the live LibraryStore.libraryTracks, which loadArtistIndex() populates.
struct ArtistDetailView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs

    let artist: LibraryStore.ArtistAgg
    let store: LibraryStore
    /// Search supplies a projected, identity-deduped set. `nil` means the normal
    /// library destination should group tracks from the browse store.
    var supplementalTracks: [UnifiedTrack]? = nil

    /// One section: a title plus the tracks under it. The "loose" group (liked/top)
    /// has a nil playlist.
    private struct Group: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let tracks: [UnifiedTrack]
    }

    /// Builds the grouped sections from the artist's library entries. A track that
    /// appears in multiple playlists shows once per playlist (that's the point of
    /// the attribution); within a group it's deduped by key.
    private var groups: [Group] {
        let entries = store.entries(forArtist: artist.name)

        var loose = supplementalTracks ?? []
        var byPlaylist: [String: (playlist: UnifiedPlaylist, tracks: [UnifiedTrack])] = [:]
        var order: [String] = []

        for entry in supplementalTracks == nil ? entries : [] {
            if let pl = entry.playlist {
                if byPlaylist[pl.key] == nil {
                    byPlaylist[pl.key] = (pl, [])
                    order.append(pl.key)
                }
                byPlaylist[pl.key]?.tracks.append(entry.track)
            } else {
                loose.append(entry.track)
            }
        }

        var result: [Group] = []
        if !loose.isEmpty {
            result.append(Group(id: "__loose__", title: "Liked & Top",
                                subtitle: nil, tracks: dedupe(loose)))
        }
        for key in order {
            guard let bucket = byPlaylist[key] else { continue }
            let pl = bucket.playlist
            result.append(Group(id: pl.key,
                                title: pl.name,
                                subtitle: pl.isMixtape ? "Mixtape" : "Playlist",
                                tracks: dedupe(bucket.tracks)))
        }
        return result
    }

    private func dedupe(_ tracks: [UnifiedTrack]) -> [UnifiedTrack] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.key).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.indexingArtists && groups.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().tint(theme.palette.rose)
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if groups.isEmpty {
                    Text("No tracks found for this artist")
                        .font(Typography.body(14))
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(groups) { group in
                        section(group)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtistAvatar(url: artist.artURL, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(Typography.heading(24))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(2)
                Text("\(artist.count) unique song\(artist.count == 1 ? "" : "s") in your library")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(Array(artist.providers), id: \.self) { pid in
                    ProviderBadge(id: pid, size: 18)
                }
            }
        }
    }

    private func section(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(Typography.semibold(13))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                if let subtitle = group.subtitle {
                    Text("· \(subtitle)")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                }
                Spacer(minLength: 4)
                Text("\(group.tracks.count)")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
            }
            .padding(.top, 14)
            .padding(.bottom, 4)

            LazyVStack(spacing: 0) {
                ForEach(Array(group.tracks.enumerated()), id: \.offset) { index, track in
                    UnifiedTrackRow(track: track) {
                        Task { await player.play(tracks: group.tracks, startingAt: index,
                                                 mode: prefs.mode, weights: prefs.weights) }
                    }
                }
            }
        }
    }
}
