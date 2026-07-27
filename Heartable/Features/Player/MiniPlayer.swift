import SwiftUI

/// Now-playing strip hosted in the tab view's bottom accessory — the system
/// supplies the Liquid Glass capsule, so this is just content: artwork,
/// title/artist, transport, with a hairline progress along the bottom edge.
/// When the tab bar minimizes on scroll the accessory moves inline and the
/// secondary controls drop away (the Apple Music condensed arrangement).
/// Presentation is owned by AppTabView so a transient player-state update cannot
/// destroy an already-open full player.
struct MiniPlayer: View {
    @Environment(PlayerStore.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let onOpen: () -> Void

    var body: some View {
        if let now = player.now {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        artwork(now.artworkURL)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(now.name).font(Typography.semibold(13))
                                .foregroundStyle(theme.palette.text).lineLimit(1)
                            Text(now.artist).font(Typography.body(11))
                                .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(now.name), \(now.artist)")
                .accessibilityHint("Opens the full player")

                if placement != .inline {
                    PlaybackModeControl(size: 15)
                    DeviceButton(source: now.source, size: 16)
                }
                Button {
                    Task { await player.toggle() }
                } label: {
                    Image(systemName: now.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(theme.palette.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(now.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { progress(now).padding(.horizontal, 14) }
        } else {
            idleRow
        }
    }

    /// The Apple Music idle state: dimmed heart square + "Not Playing".
    private var idleRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.palette.surface)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.palette.textMuted.opacity(0.6))
                }
            Text("Not Playing")
                .font(Typography.semibold(13))
                .foregroundStyle(theme.palette.textMuted)
            Spacer(minLength: 8)
            Image(systemName: "play.fill")
                .font(.system(size: 19))
                .foregroundStyle(theme.palette.textMuted.opacity(0.5))
                .frame(width: 34, height: 34)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    private func artwork(_ url: URL?) -> some View {
        CoverArt(url: url, size: 34, corner: 8, placeholderScale: 0.3)
    }

    private func progress(_ now: PlayerStore.Now) -> some View {
        GeometryReader { geo in
            let pct = now.durationMs > 0 ? min(1, Double(now.positionMs) / Double(now.durationMs)) : 0
            Capsule().fill(theme.palette.rose)
                .frame(width: geo.size.width * pct, height: 2)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
