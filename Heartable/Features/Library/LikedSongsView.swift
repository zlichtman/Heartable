import SwiftUI

/// "Heartables" — the master liked-songs list: every liked track merged across
/// all connected services into one playlist-style screen. Reads from the live
/// `LibraryStore` so it fills in as providers finish loading.
struct LikedSongsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs
    let store: LibraryStore
    // Network paging alone does not bound the initial SwiftUI list diff. Keep
    // first presentation small even when thousands of songs are already cached.
    @State private var visibleLimit = 100

    private var tracks: [UnifiedTrack] { store.likedTracks }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowBackground(theme.palette.bg)
            if let notice = store.providerNotice {
                Text(notice)
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(theme.palette.bg)
            }
            if tracks.isEmpty && !store.loadingLiked {
                Text("No Heartables yet. Like a song on any service and it lands here.")
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(theme.palette.bg)
            }
            ForEach(tracks.prefix(visibleLimit)) { track in
                UnifiedTrackRow(track: track, isEnabled: ProviderPlayback.isPlayable(track)) {
                    guard let index = tracks.firstIndex(where: { $0.key == track.key }) else { return }
                    Task { await player.play(tracks: tracks, startingAt: index,
                                             mode: prefs.mode) }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(theme.palette.bg)
            }
            if visibleLimit < tracks.count {
                Button {
                    visibleLimit = min(visibleLimit + 100, tracks.count)
                } label: {
                    Text("Show next \(min(100, tracks.count - visibleLimit)) songs")
                        .font(Typography.semibold(14))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("likedSongs.loadMore")
                .listRowSeparator(.hidden)
                .listRowBackground(theme.palette.bg)
            }
            if store.loadingLiked {
                HStack {
                    ProgressView()
                    Text("Loading Heartables… \(tracks.count) songs available")
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(theme.palette.bg)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Heartables")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { MainThreadStallMonitor.note("open Heartables (\(tracks.count) songs)") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(LinearGradient(colors: [theme.palette.grad1, theme.palette.rose],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Heartables")
                    .font(Typography.heading(24))
                    .foregroundStyle(theme.palette.text)
                Text("\(tracks.count) song\(tracks.count == 1 ? "" : "s") · all services")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Spacer(minLength: 4)
            if tracks.contains(where: { ProviderPlayback.isPlayable($0) }) {
                Button {
                    Task { await player.play(tracks: tracks, mode: prefs.mode) }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(theme.palette.rose)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play Heartables")
            }
        }
    }
}
