import SwiftUI

/// One card per playlist occurrence, even when several songs share album art.
/// Uses the same artwork cache and playback router as the regular track list.
struct PlaylistCoverBrowser: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tracks: [UnifiedTrack]
    @Binding var selection: Int?

    var body: some View {
        GeometryReader { geometry in
            let coverSize = max(80, min(280, geometry.size.height - 78))
            let cardWidth = coverSize + 24
            let reduceMotion = reduceMotion
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        Button {
                            selection = index
                            Task { await player.play(track) }
                        } label: {
                            VStack(spacing: 8) {
                                CoverArt(url: track.albumArt, size: coverSize, corner: 18)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(theme.palette.text)
                                            .frame(width: 44, height: 44)
                                            .background(theme.palette.card.opacity(0.95), in: Circle())
                                            .padding(8)
                                    }
                                VStack(spacing: 3) {
                                    Text(track.name)
                                        .font(Typography.semibold(15))
                                        .foregroundStyle(theme.palette.text)
                                    Text(track.artistNames)
                                        .font(Typography.body(12))
                                        .foregroundStyle(theme.palette.textSecondary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                            }
                            .frame(width: cardWidth)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(track.name) by \(track.artistNames)")
                        .id(index)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.9)
                                .opacity(reduceMotion || phase.isIdentity ? 1 : 0.75)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(16, (geometry.size.width - cardWidth) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection, anchor: .center)
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
        .background(theme.palette.bg.ignoresSafeArea())
    }
}
