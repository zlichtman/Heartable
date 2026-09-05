import SwiftUI

/// Rotation changes only the presentation. The shelf retains the playlist's
/// occurrence order, cached artwork, and existing playback queue.
struct PlaylistCoverBrowser: View {
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs

    let tracks: [UnifiedTrack]
    @Binding var selection: Int?

    var body: some View {
        PlaylistVinylShelf(tracks: tracks, selection: $selection) { index in
            Task {
                await player.play(tracks: tracks, startingAt: index,
                                  mode: prefs.mode, weights: prefs.weights)
            }
        }
    }
}

/// Stable-width slots keep scrolling predictable while the focused jacket is
/// pulled out visually. Only visible sleeves create artwork views, even for a
/// very large playlist. The presentation has no provider or network ownership.
struct PlaylistVinylShelf: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tracks: [UnifiedTrack]
    @Binding var selection: Int?
    let onPlay: (Int) -> Void

    private var focusedIndex: Int? {
        VinylShelfLayout.validSelection(selection, count: tracks.count)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = VinylShelfLayout(height: geometry.size.height)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    shelf(layout: layout, width: geometry.size.width)
                    if let index = focusedIndex {
                        trackLabel(tracks[index], index: index)
                    }
                }
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .onChange(of: tracks.count, initial: true) {
            selection = focusedIndex
        }
    }

    private func shelf(layout: VinylShelfLayout, width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .bottom, spacing: layout.spacing) {
                ForEach(tracks.indices, id: \.self) { index in
                    let focused = index == focusedIndex
                    Button {
                        selection = index
                        onPlay(index)
                    } label: {
                        VinylSleeve(track: tracks[index], size: layout.coverSize, focused: focused)
                            .rotation3DEffect(.degrees(focused ? 0 : -66),
                                              axis: (x: 0, y: 1, z: 0), perspective: 0.25)
                            .scaleEffect(focused ? 1 : 0.92, anchor: .bottom)
                            .offset(y: focused ? -7 : 0)
                            .frame(width: layout.slotWidth, height: layout.coverSize, alignment: .bottom)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(tracks[index].name) by \(tracks[index].artistNames)")
                    .accessibilityValue("\(index + 1) of \(tracks.count)")
                    .accessibilityAddTraits(focused ? [.isSelected] : [])
                    .id(index)
                    .zIndex(focused ? 1_000 : Double(-abs(index - (focusedIndex ?? 0))))
                }
            }
            .scrollTargetLayout()
            .padding(.top, 18)
            .padding(.bottom, 16)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: focusedIndex)
        }
        .contentMargins(.horizontal, max(0, (width - layout.slotWidth) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selection, anchor: .center)
        .defaultScrollAnchor(.center, for: .initialOffset)
        .defaultScrollAnchor(.center, for: .sizeChanges)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(height: layout.coverSize + 34)
        .background(alignment: .bottom) { shelfLedge }
        .clipped()
        .accessibilityIdentifier("playlist.vinylShelf")
    }

    private var shelfLedge: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.palette.textSecondary.opacity(0.22))
                .frame(height: 5)
            Rectangle()
                .fill(LinearGradient(colors: [theme.palette.textSecondary.opacity(0.32), theme.palette.surface],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 11)
            Rectangle().fill(theme.palette.border).frame(height: 1)
        }
        .shadow(color: theme.palette.text.opacity(0.10), radius: 5, y: 4)
        .accessibilityHidden(true)
    }

    private func trackLabel(_ track: UnifiedTrack, index: Int) -> some View {
        HStack(spacing: 14) {
            Text("\(index + 1) / \(tracks.count)")
                .font(Typography.medium(11))
                .monospacedDigit()
                .foregroundStyle(theme.palette.textMuted)
                .accessibilityLabel("Song \(index + 1) of \(tracks.count)")
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                Text(track.artistNames)
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { onPlay(index) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.palette.text)
                    .frame(width: 48, height: 48)
                    .background(theme.palette.roseDim, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(track.name)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

private struct VinylSleeve: View {
    @Environment(ThemeStore.self) private var theme
    let track: UnifiedTrack
    let size: CGFloat
    let focused: Bool

    var body: some View {
        ZStack {
            if focused {
                // A physical record peeks out of its jacket, not a substitute
                // for the song's own artwork. No repeating/spinning animation.
                Circle().fill(.black)
                    .overlay {
                        ForEach([0.88, 0.78, 0.68], id: \.self) { scale in
                            Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                                .padding(size * (1 - scale) / 2)
                        }
                        Circle().fill(theme.palette.rose).padding(size * 0.34)
                        Circle().fill(theme.palette.surface).padding(size * 0.47)
                    }
                    .frame(width: size * 0.92, height: size * 0.92)
                    .offset(x: size * 0.17)
            }
            CoverArt(url: track.albumArt, size: size, corner: 3)
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [.black.opacity(0.26), .white.opacity(0.12), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 9)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(theme.palette.text.opacity(0.14), lineWidth: 1)
                }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(focused ? 0.25 : 0.16), radius: focused ? 7 : 2, x: 3, y: 5)
        .accessibilityHidden(true)
    }
}

struct VinylShelfLayout {
    let coverSize: CGFloat
    var slotWidth: CGFloat { max(44, coverSize * 0.48) }
    let spacing: CGFloat = 4

    init(height: CGFloat) {
        coverSize = max(72, min(260, height - 102))
    }

    static func validSelection(_ selection: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(count - 1, max(0, selection ?? 0))
    }
}
