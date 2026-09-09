import SwiftUI

/// A Liquid Glass "now playing" island: album art, a live rose label with an
/// inline `Visualizer`, and the track title/artist. Handles both the playing and
/// the quiet (nothing playing) states so it can headline a profile hero. Reused
/// wherever a friend's live listening status is the emotional centerpiece.
struct NowPlayingStrip: View {
    @Environment(ThemeStore.self) private var theme

    let trackName: String?
    let artist: String?
    /// Album-art URL string (matches the `now_playing` payload shape).
    let albumArt: String?
    let isPlaying: Bool
    /// ISO8601 timestamp of the last update, used for the "paused Xh ago" line.
    var updatedAt: String? = nil

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 20, style: .continuous) }

    private var hasTrack: Bool { !(trackName ?? "").isEmpty }

    var body: some View {
        HStack(spacing: 13) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                statusLabel
                if hasTrack {
                    Text(trackName ?? "")
                        .font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(1)
                    if let artist, !artist.isEmpty {
                        Text(artist)
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Their status updates while their Heartable app is open.")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if hasTrack {
                Visualizer(isPlaying: isPlaying, barCount: 5)
                    .frame(width: 26, height: 22)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(theme.palette.rose.opacity(hasTrack ? 0.16 : 0.06)), in: shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasTrack ? (isPlaying ? "Listening now" : "Paused") : "Not listening")
        .accessibilityValue(hasTrack
                            ? [trackName, artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                            : "Their status updates while Heartable is open")
    }

    private var artwork: some View {
        Group {
            if hasTrack {
                ArtworkThumb(urlString: albumArt, size: 52, corner: 12)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.palette.surface)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.palette.textMuted)
                    }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if hasTrack {
            Text(isPlaying ? "LISTENING NOW" : pausedLabel)
                .font(Typography.semibold(10))
                .tracking(1.2)
                .foregroundStyle(theme.palette.rose)
                .lineLimit(1)
        } else {
            Text("NOT LISTENING")
                .font(Typography.semibold(10))
                .tracking(1.2)
                .foregroundStyle(theme.palette.textMuted)
        }
    }

    private var pausedLabel: String {
        guard let updatedAt, !updatedAt.isEmpty else { return "PAUSED" }
        let ago = relativeLong(updatedAt).uppercased()
        return ago.isEmpty ? "PAUSED" : "PAUSED \(ago)"
    }
}
