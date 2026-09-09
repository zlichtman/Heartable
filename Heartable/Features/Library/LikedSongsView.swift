import SwiftUI

/// "Heartables" — the master liked-songs list: every liked track merged across
/// all connected services into one playlist-style screen. Reads from the live
/// `LibraryStore` so it fills in as providers finish loading.
struct LikedSongsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs
    let store: LibraryStore

    private var tracks: [UnifiedTrack] { store.likedTracks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if tracks.isEmpty {
                    Text(store.loading ? "Loading…" : "No Heartables yet. Like a song on any service and it lands here.")
                        .font(Typography.body(14))
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            UnifiedTrackRow(track: track) {
                                Task { await player.play(tracks: tracks, startingAt: index,
                                                         mode: prefs.mode, weights: prefs.weights) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Heartables")
        .navigationBarTitleDisplayMode(.inline)
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
            if !tracks.isEmpty {
                Button {
                    Task { await player.play(tracks: tracks, mode: prefs.mode, weights: prefs.weights) }
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
