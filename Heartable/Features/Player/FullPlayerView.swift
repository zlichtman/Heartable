import SwiftUI

/// Presentation and lyrics lifetime stay stable when the player rotates.
struct FullPlayerView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var lyrics = LyricsModel()

    var body: some View {
        ZStack {
            theme.palette.playerBackdrop.ignoresSafeArea()
            theme.palette.bg.opacity(0.92).ignoresSafeArea()

            if let now = player.now {
                FullPlayerContent(now: now, lyrics: lyrics) { showLyrics = true }
                .onChange(of: now.uri, initial: true) {
                    if !now.source.isLiveRadio { lyrics.load(for: now) }
                }
                .sheet(isPresented: $showLyrics) {
                    LyricsSheet(model: lyrics)
                        .environment(theme)
                        .environment(player)
                        .heartableSheetChrome(dragIndicator: .hidden)
                }
            } else {
                idlePlayer
            }
        }
    }

    private var idlePlayer: some View {
        VStack(spacing: 0) {
            HStack {
                HeartableNavigationButton(kind: .dismiss, accessibilityLabel: "Dismiss player",
                                          action: dismiss.callAsFunction)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(theme.palette.textMuted)
                Text("Nothing playing")
                    .font(Typography.body(16))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Spacer()
        }
    }
}

/// Both orientations share actions and local scrubbing state. Landscape is a
/// bounded two-column surface, never the portrait scroller squeezed sideways.
struct FullPlayerContent: View {
    @Environment(PlayerStore.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType

    let now: PlayerStore.Now
    let lyrics: LyricsModel
    let onLyrics: () -> Void

    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0
    @State private var showRemaining = false

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscape(size: proxy.size)
            } else {
                portrait(size: proxy.size)
            }
        }
    }

    private func artwork(side: CGFloat) -> some View {
        CoverArt(url: now.artworkURL, size: side, corner: min(28, side * 0.10), placeholderScale: 0.18)
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
            .accessibilityHidden(true)
    }

    private func portrait(size: CGSize) -> some View {
        let compact = size.height < 650 || dynamicType.isAccessibilitySize
        return VStack(spacing: compact ? 8 : 12) {
            playerHeader(now).frame(height: 44)
            GeometryReader { geometry in
                let side = max(0, min(geometry.size.width, geometry.size.height, 420))
                artwork(side: side)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(minHeight: 0)
            .layoutPriority(-1)
            .playerElement("artwork")
            trackInfo(now, compact: compact, centered: true)
            scrubber(now, compact: true)
            transport(now, compact: compact || size.width < 360)
            if !now.source.isLiveRadio {
                LyricsCard(model: lyrics, positionMs: now.positionMs,
                           height: dynamicType.isAccessibilitySize ? 100 : 64, onExpand: onLyrics)
                    .playerElement("lyrics")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 12 : 16)
        .frame(width: size.width, height: size.height)
    }

    private func landscape(size: CGSize) -> some View {
        let layout = FullPlayerLandscapeLayout(size: size, largeText: dynamicType.isAccessibilitySize,
                                              hasLyrics: !now.source.isLiveRadio)
        return VStack(spacing: 8) {
            playerHeader(now)
                .frame(height: 44)
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 8) {
                    artwork(side: layout.artSide)
                        .playerElement("artwork")
                    if layout.lyricsBesideControls {
                        landscapeLyrics(height: layout.lyricsHeight)
                    }
                }
                .frame(width: layout.artWidth, height: layout.columnHeight, alignment: .top)
                VStack(spacing: 4) {
                    trackInfo(now, compact: true)
                        .frame(height: dynamicType.isAccessibilitySize ? max(0, layout.columnHeight - 112) : nil,
                               alignment: .top)
                    Spacer(minLength: 0)
                    if !now.source.isLiveRadio && !layout.lyricsBesideControls {
                        landscapeLyrics(height: layout.lyricsHeight)
                    }
                    scrubber(now, compact: true)
                    transport(now, compact: true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: layout.columnHeight)
            }
            .frame(height: layout.contentHeight)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(width: size.width, height: size.height, alignment: .top)
        .accessibilityIdentifier("player.landscape")
    }

    private func landscapeLyrics(height: CGFloat) -> some View {
        LyricsCard(model: lyrics, positionMs: now.positionMs, height: height, onExpand: onLyrics)
            .playerElement("lyrics")
    }

    private func playerHeader(_ now: PlayerStore.Now) -> some View {
        HStack {
            dismissButton

            Spacer()
            Text(sourceLabel(now.source))
                .font(Typography.medium(12))
                .foregroundStyle(theme.palette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer()
            DeviceButton(source: now.source, size: 20)
                .playerElement("device")
        }
    }

    private var dismissButton: some View {
        HeartableNavigationButton(
            kind: .dismiss,
            accessibilityLabel: "Dismiss player",
            action: dismiss.callAsFunction
        )
        .playerElement("dismiss")
    }

    private func trackInfo(_ now: PlayerStore.Now, compact: Bool = false, centered: Bool = false) -> some View {
        let leading = compact && !centered
        return VStack(alignment: leading ? .leading : .center, spacing: compact ? 2 : 6) {
            Text(now.name).font(Typography.heading(compact ? 20 : 24))
                .foregroundStyle(theme.palette.text)
                .multilineTextAlignment(leading ? .leading : .center).lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(compact ? 0.75 : 1)
            Text(now.artist).font(Typography.body(compact ? 14 : 16))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(leading ? .leading : .center)
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(compact ? 0.75 : 1)
            if !compact {
                Visualizer(isPlaying: now.isPlaying)
                    .frame(height: 20)
                    .frame(maxWidth: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
        .accessibilityElement(children: .combine)
        .playerElement("trackInfo")
    }

    private func scrubber(_ now: PlayerStore.Now, compact: Bool = false) -> some View {
        // Live radio / unknown length: render a quiet, non-interactive idle bar.
        let hasDuration = now.durationMs > 0
        let livePct = hasDuration ? min(1, Double(now.positionMs) / Double(now.durationMs)) : 0
        // While dragging, follow the local fraction so the live poll can't fight it.
        let fraction = isScrubbing ? scrubFraction : livePct
        let displayedMs = isScrubbing ? Int(fraction * Double(now.durationMs)) : now.positionMs
        let remainingMs = max(0, now.durationMs - displayedMs)

        let bar = Group {
            GeometryReader { geo in
                let w = geo.size.width
                let thumbSize: CGFloat = isScrubbing ? 16 : 12
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.palette.border).frame(height: 4)
                    if hasDuration {
                        Capsule().fill(theme.palette.rose)
                            .frame(width: max(0, w * fraction), height: 4)
                        Circle().fill(theme.palette.rose)
                            .frame(width: thumbSize, height: thumbSize)
                            .offset(x: min(max(0, w * fraction - thumbSize / 2), w - thumbSize))
                            .animation(.easeOut(duration: 0.15), value: isScrubbing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: w, now: now), including: hasDuration ? .all : .none)
            }
            .frame(height: 24)
        }
        let elapsed = Text(timeString(displayedMs)).font(Typography.body(11))
            .foregroundStyle(theme.palette.textMuted).monospacedDigit()
        let duration = Button {
            if hasDuration { showRemaining.toggle() }
        } label: {
            Text(showRemaining ? "-" + timeString(remainingMs) : timeString(now.durationMs))
                .font(Typography.body(11))
                .foregroundStyle(theme.palette.textMuted)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasDuration)
        .accessibilityLabel(showRemaining ? "Show total duration" : "Show remaining time")
        return Group {
            if compact {
                HStack(spacing: 10) { elapsed; bar; duration }
                    .frame(height: 44)
            } else {
                VStack(spacing: 4) {
                    bar
                    HStack { elapsed; Spacer(); duration }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback position")
        .accessibilityValue(hasDuration
                            ? "\(timeString(displayedMs)) of \(timeString(now.durationMs))"
                            : "Live")
        .accessibilityAdjustableAction { direction in
            guard hasDuration else { return }
            let delta = direction == .increment ? 15_000 : -15_000
            let target = min(now.durationMs, max(0, displayedMs + delta))
            Task { await player.seek(toMs: target) }
        }
        .playerElement("scrubber")
    }

    /// A tap (drag of zero distance) or drag anywhere on the bar seeks the track.
    /// While active, `isScrubbing` holds `scrubFraction` so the display renders from
    /// the finger instead of the live player position; drag-end commits the seek.
    private func scrubGesture(width: CGFloat, now: PlayerStore.Now) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isScrubbing = true
                scrubFraction = min(1, max(0, value.location.x / width))
            }
            .onEnded { value in
                let f = min(1, max(0, value.location.x / width))
                scrubFraction = f
                let target = Int(f * Double(now.durationMs))
                // Keep rendering from the finger until the seek lands; the store
                // reflects the target optimistically on return, so releasing
                // never snaps the thumb back to the pre-seek position.
                Task {
                    await player.seek(toMs: target)
                    isScrubbing = false
                }
            }
    }

    /// Transport row: the shuffle / playback-mode control flanks the leading edge
    /// so the active mode is always visible, prev / play / next stay centered, and
    /// an equal-width clear spacer on the trailing edge keeps the play disc optically
    /// in the middle without crowding it.
    private func transport(_ now: PlayerStore.Now, compact: Bool = false) -> some View {
        HStack(spacing: 0) {
            PlaybackModeControl(size: 22)
                .playerElement("mode")
            Spacer(minLength: 0)
            HStack(spacing: compact ? 12 : 28) {
                control("backward.fill", label: "Previous track", size: 26) {
                    Task { await player.prev() }
                }
                playButton(now, compact: compact)
                control("forward.fill", label: "Next track", size: 26) {
                    Task { await player.next() }
                }
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
        .playerElement("transport")
    }

    /// Clean, minimal primary play/pause control: a solid disc with the glyph
    /// knocked out in the background color. Replaces the heavy filled-circle symbol.
    private func playButton(_ now: PlayerStore.Now, compact: Bool = false) -> some View {
        Button { Task { await player.toggle() } } label: {
            ZStack {
                Circle().fill(theme.palette.text).frame(width: compact ? 56 : 68, height: compact ? 56 : 68)
                Image(systemName: now.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(theme.palette.bg)
                    // Optically center the asymmetric play triangle.
                    .offset(x: now.isPlaying ? 0 : 2)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(now.isPlaying ? "Pause" : "Play")
        .playerElement("playPause")
    }

    private func control(_ symbol: String, label: String, size: CGFloat,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
                .foregroundStyle(theme.palette.text)
                .frame(width: max(44, size + 22), height: max(44, size + 22))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .playerElement(symbol == "backward.fill" ? "previous" : "next")
    }

    private func sourceLabel(_ id: ProviderID) -> String {
        ProviderCatalog.entry(id)?.label.uppercased() ?? id.rawValue.uppercased()
    }

    private func timeString(_ ms: Int) -> String {
        let s = max(0, ms / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Rendered frames allow layout regression tests to check real controls, not
/// just arithmetic or the outer container. No view state depends on this probe.
struct PlayerElementFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func playerElement(_ name: String) -> some View {
        accessibilityIdentifier("player.\(name)")
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: PlayerElementFrames.self,
                                           value: [name: geometry.frame(in: .global)])
                }
            }
    }
}

struct FullPlayerLandscapeLayout {
    let contentHeight: CGFloat
    let columnHeight: CGFloat
    let artWidth: CGFloat
    let artSide: CGFloat
    let lyricsHeight: CGFloat
    let lyricsBesideControls: Bool

    init(size: CGSize, largeText: Bool = false, hasLyrics: Bool = true) {
        contentHeight = max(0, size.height - 68) // 44pt header, 8pt gap, 16pt padding
        lyricsBesideControls = largeText && hasLyrics
        lyricsHeight = largeText ? 90 : (contentHeight < 218 ? 44 : 56)
        // The artwork and controls share a single vertical footprint. Large
        // accessibility text gets a second row under the artwork for lyrics.
        columnHeight = largeText ? contentHeight : min(contentHeight, max(0, (size.width - 64) * 0.44))
        artSide = max(0, columnHeight - (lyricsBesideControls ? lyricsHeight + 8 : 0))
        artWidth = lyricsBesideControls ? max(artSide, (size.width - 64) * 0.34) : artSide
    }
}

/// Lyrics panel presented from the full player. Shows synced lines (with the
/// active line highlighted in `rose`) when available, plain text as a fallback,
/// otherwise a quiet placeholder.
private struct LyricsSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss

    let model: LyricsModel

    private var positionMs: Int { player.now?.positionMs ?? 0 }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.palette.bg.ignoresSafeArea())
                .navigationTitle("Lyrics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HeartableNavigationButton(
                            kind: .dismiss,
                            accessibilityLabel: "Dismiss lyrics",
                            drawsSurface: false,
                            action: dismiss.callAsFunction
                        )
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loading {
            ProgressView().tint(theme.palette.rose)
        } else if !model.synced.isEmpty {
            syncedList
        } else if let plain = model.plain, !plain.isEmpty {
            plainView(plain)
        } else {
            Text("No lyrics found.")
                .font(Typography.body(15))
                .foregroundStyle(theme.palette.textMuted)
        }
    }

    private var syncedList: some View {
        let active = model.currentIndex(positionMs: positionMs)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(model.synced.enumerated()), id: \.offset) { pair in
                        lineView(text: pair.element.text, isActive: pair.offset == active)
                            .id(pair.offset)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: active) { _, new in
                guard let new else { return }
                withAnimation(.easeInOut) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func lineView(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(isActive ? Typography.semibold(18) : Typography.body(17))
            .foregroundStyle(isActive ? theme.palette.rose : theme.palette.textMuted)
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private func plainView(_ plain: String) -> some View {
        ScrollView {
            Text(plain)
                .font(Typography.body(16))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
}
