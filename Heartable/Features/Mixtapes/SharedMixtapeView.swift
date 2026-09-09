import SwiftUI

struct SharedMixtapeView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(AuthStore.self) private var auth
    @Environment(PlaybackPrefsStore.self) private var prefs
    let route: SharedMixtapeRoute
    @State private var snapshot: SharedMixtapeSnapshot?
    @State private var failed = false
    @State private var reload = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let snapshot {
                        if let cover = snapshot.cover_url { ArtworkThumb(urlString: cover, size: 200, corner: 16) }
                        Text(snapshot.title ?? "Mixtape").font(Typography.heading(28))
                        if let text = snapshot.description, !text.isEmpty { Text(text).font(Typography.body(16)) }
                        ForEach(snapshot.tracks) { track in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.track_name ?? "Untitled track").font(Typography.semibold(16))
                                        Text(track.artist ?? "").font(Typography.body(14)).foregroundStyle(theme.palette.textSecondary)
                                    }
                                    Spacer()
                                    if auth.userID != nil, let song = unified(track) {
                                        Button {
                                            Task { await player.play(tracks: [song], mode: prefs.mode, weights: prefs.weights) }
                                        } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }
                                        .accessibilityLabel("Play \(track.track_name ?? "track")")
                                    }
                                }
                                if let note = track.note, !note.isEmpty { Text(note).font(Typography.body(15)) }
                                if let image = track.note_image_url { ArtworkThumb(urlString: image, size: 200, corner: 12) }
                            }
                            Divider().overlay(theme.palette.border)
                        }
                        if auth.userID == nil {
                            Text("Sign in to Heartable and connect a music service to play these songs.")
                                .font(Typography.body(14)).foregroundStyle(theme.palette.textSecondary)
                        }
                    } else {
                        Text(failed ? "This mixtape couldn’t be opened. The link may have been revoked." : "Opening mixtape…")
                            .font(Typography.body(16))
                        if failed { Button("Try again") { reload = UUID() } }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(theme.palette.text)
            .background(theme.palette.bg.ignoresSafeArea())
            .navigationTitle("Mixtape").navigationBarTitleDisplayMode(.inline)
        }
        .heartableSheetChrome()
        .task(id: reload) {
            failed = false
            do { snapshot = try await SharedMixtapeSnapshot.load(token: route.token) }
            catch { if !Task.isCancelled { failed = true } }
        }
    }

    private func unified(_ track: SharedMixtapeSnapshot.Track) -> UnifiedTrack? {
        guard let uri = track.track_uri, let raw = uri.split(separator: ":").first,
              let provider = ProviderID(rawValue: String(raw)) else { return nil }
        return UnifiedTrack(key: uri, providerID: provider, providerTrackID: String(uri.split(separator: ":").last ?? ""),
                            uri: uri, name: track.track_name ?? "", artists: [UnifiedArtist(id: track.artist ?? "", name: track.artist ?? "")],
                            album: nil, albumArt: nil, durationMs: 0)
    }
}
