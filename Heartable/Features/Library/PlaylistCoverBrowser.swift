import SwiftUI

extension EnvironmentValues {
    @Entry var playlistPlayerFrame: CGRect? = nil
}

/// Native bottom accessories can update their safe-area proposal separately
/// from navigation/rotation. Bound the vinyl canvas by the actual accessory
/// in the same global coordinate space, not by a guessed bar height or a timer.
struct PlaylistVinylViewport<Content: View>: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.playlistPlayerFrame) private var playerFrame
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geometry in
            let size = PlaylistViewportBounds.availableSize(
                bounds: geometry.frame(in: .global), player: playerFrame)
            content(size)
                .frame(width: size.width, height: size.height)
                .clipped()
                .transaction { $0.animation = nil }
        }
        .background(theme.palette.bg.ignoresSafeArea())
    }
}

enum PlaylistViewportBounds {
    static func availableSize(bounds: CGRect, player: CGRect?) -> CGSize {
        guard let player, player.width > 0, player.height > 0,
              player.minX < bounds.maxX, player.maxX > bounds.minX,
              player.minY >= bounds.minY, player.minY < bounds.maxY else {
            return bounds.size
        }
        return CGSize(width: bounds.width, height: max(0, player.minY - bounds.minY - 8))
    }
}

/// The physical ledge, not UIScrollView's system-extended transparent bounds.
/// Layout tests consume this preference to verify the rendered shelf footprint.
struct VinylShelfLedgeFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

struct PlaylistCoverBrowser: View {
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs

    let tracks: [UnifiedTrack]
    @Binding var selection: Int?
    let viewportSize: CGSize

    var body: some View {
        PlaylistVinylShelf(tracks: tracks, selection: $selection, viewportSize: viewportSize) { index in
            Task {
                await player.play(tracks: tracks, startingAt: index,
                                  mode: prefs.mode, weights: prefs.weights)
            }
        }
    }
}

/// A fixed-height, two-pane landscape browser. The shelf and its caption share
/// the safe content area instead of stacking inside a second vertical scroller.
/// Only visible sleeves create artwork views, even for a very large playlist.
struct PlaylistVinylShelf: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tracks: [UnifiedTrack]
    @Binding var selection: Int?
    var viewportSize: CGSize? = nil
    let onPlay: (Int) -> Void

    private var focusedIndex: Int? {
        VinylShelfLayout.validSelection(selection, count: tracks.count)
    }

    var body: some View {
        GeometryReader { geometry in
            // Use the parent's bounded size, not a second independently changing
            // safe-area proposal. Geometry here supplies position only.
            let size = viewportSize.map {
                CGSize(width: max(0, $0.width - 40), height: max(0, $0.height - 24))
            } ?? geometry.size
            let layout = VinylShelfLayout(size: size)
            HStack(spacing: layout.panelSpacing) {
                shelf(layout: layout, centerX: geometry.frame(in: .global).minX + layout.shelfWidth / 2)
                    .frame(width: layout.shelfWidth)
                if let index = focusedIndex {
                    ScrollView(.vertical) {
                        trackLabel(tracks[index], index: index)
                            .padding(.trailing, 16)
                            .frame(minHeight: size.height, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: layout.captionWidth)
                    .accessibilityIdentifier("playlist.vinylCaption")
                }
            }
            .frame(width: size.width, height: size.height)
            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(theme.palette.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(theme.palette.bg.ignoresSafeArea())
        .onChange(of: tracks.count, initial: true) {
            selection = focusedIndex
        }
    }

    private func shelf(layout: VinylShelfLayout, centerX: CGFloat) -> some View {
        let anchor = UnitPoint(x: CGFloat(focusedIndex ?? 0) / CGFloat(max(1, tracks.count - 1)), y: 0.5)
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .center, spacing: layout.spacing) {
                ForEach(tracks.indices, id: \.self) { index in
                    sleeveButton(index: index, layout: layout, centerX: centerX)
                        .id(index)
                        .zIndex(index == focusedIndex ? 1_000 : Double(-abs(index - (focusedIndex ?? 0))))
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 14)
        }
        // Margins are based on stable scroll targets, not the wider artwork.
        // The first/last sleeve can therefore land at exactly the same center.
        .contentMargins(.horizontal, layout.endMargin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selection, anchor: .center)
        .defaultScrollAnchor(anchor, for: .initialOffset)
        .defaultScrollAnchor(anchor, for: .sizeChanges)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(height: layout.shelfHeight)
        .background(theme.palette.surface)
        .overlay(alignment: .bottom) { shelfLedge.allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.palette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        // Equal-width targets and symmetric end margins make the selected
        // occurrence an exact fraction of the scroll range. A new viewport gets
        // that initial anchor, not the previous viewport's stale pixel offset.
        // Only this lazy shelf is rebuilt; selection, portrait rows and cache stay.
        .id(layout)
        .transaction { $0.animation = nil }
        .accessibilityIdentifier("playlist.vinylShelf")
    }


    private func sleeveButton(index: Int, layout: VinylShelfLayout, centerX: CGFloat) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                selection = index
            }
            onPlay(index)
        } label: {
            sleeveArtwork(index: index, layout: layout, centerX: centerX)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(tracks[index].name) by \(tracks[index].artistNames)")
        .accessibilityValue("\(index + 1) of \(tracks.count)")
        .accessibilityAddTraits(index == focusedIndex ? [.isSelected] : [])
        .accessibilityIdentifier("playlist.vinylSleeve.\(index)")
    }

    private func sleeveArtwork(index: Int, layout: VinylShelfLayout, centerX: CGFloat) -> some View {
        let motionReduced = reduceMotion
        return VinylSleeve(track: tracks[index], size: layout.coverSize, focused: index == focusedIndex)
            .frame(width: layout.slotWidth, height: layout.coverSize)
            .visualEffect { content, geometry in
                // Scroll-content margins affect the built-in scroll coordinate
                // space. Compare viewport and sleeve in the same global space.
                let center = geometry.frame(in: .global).midX
                let distance = (center - centerX) / layout.step
                let pose = VinylShelfPose(distance: distance, coverSize: layout.coverSize,
                                          reduceMotion: motionReduced)
                return content
                    .rotation3DEffect(.degrees(pose.angle), axis: (x: 0, y: 1, z: 0), perspective: 0.2)
                    .scaleEffect(pose.scale)
                    .offset(x: pose.offsetX, y: pose.offsetY)
            }
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
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: theme.palette.text.opacity(0.10), radius: 5, y: 4)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: VinylShelfLedgeFrameKey.self, value: geometry.frame(in: .global))
            }
        }
        .accessibilityHidden(true)
    }

    private func trackLabel(_ track: UnifiedTrack, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(index + 1) / \(tracks.count)")
                .font(Typography.medium(11))
                .monospacedDigit()
                .foregroundStyle(theme.palette.textMuted)
                .accessibilityLabel("Song \(index + 1) of \(tracks.count)")
            VStack(alignment: .leading, spacing: 6) {
                Text(track.name)
                    .font(Typography.heading(22))
                    .foregroundStyle(theme.palette.text)
                Text(track.artistNames)
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
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
                    .offset(x: size * 0.13)
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

/// Pure viewport/pose math is shared with regression tests. No scroll-time
/// observable writes are needed to animate a sleeve through the center.
struct VinylShelfLayout: Hashable {
    let coverSize: CGFloat
    let shelfWidth: CGFloat
    let captionWidth: CGFloat
    let panelSpacing: CGFloat = 24
    let spacing: CGFloat = 4
    var slotWidth: CGFloat { max(44, coverSize * 0.60) }
    var step: CGFloat { slotWidth + spacing }
    var endMargin: CGFloat { max(0, (shelfWidth - slotWidth) / 2) }
    var shelfHeight: CGFloat { coverSize + 28 }

    init(size: CGSize) {
        captionWidth = min(260, max(160, size.width * 0.30))
        shelfWidth = max(0, size.width - captionWidth - panelSpacing)
        coverSize = max(0, min(260, size.height - 28, shelfWidth / 1.6))
    }

    static func validSelection(_ selection: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(count - 1, max(0, selection ?? 0))
    }
}

struct VinylShelfPose {
    let angle: Double
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat

    init(distance: CGFloat, coverSize: CGFloat, reduceMotion: Bool) {
        let side = min(1, max(-1, distance))
        let progress = abs(side)
        angle = reduceMotion ? 0 : -Double(side) * 54
        scale = reduceMotion ? 1 : 1 - 0.10 * progress
        // Open a gap around the face-on jacket; neighboring sleeves never cut
        // across it. Outer jackets still nest lightly like records on a shelf.
        offsetX = side * coverSize * (reduceMotion ? 0.46 : 0.24)
        offsetY = reduceMotion ? 0 : progress * 4
    }
}
