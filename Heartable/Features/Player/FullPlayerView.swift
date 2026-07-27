import SwiftUI

/// Full-screen now-playing: artwork, title/artist, transport, scrubber. Phase 7
/// adds the skip-version + 3-dot menu surfaces.
struct FullPlayerView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(PlaybackPrefsStore.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0
    @State private var showRemaining = false

    var body: some View {
        ZStack {
            theme.palette.playerBackdrop.ignoresSafeArea()
            theme.palette.bg.opacity(0.92).ignoresSafeArea()

            if let now = player.now {
                GeometryReader { proxy in
                    let artSide = max(
                        180,
                        min(min(proxy.size.width - 48, proxy.size.height * 0.42), 420)
                    )

                    ScrollView {
                        VStack(spacing: 24) {
                            playerHeader(now)

                            CoverArt(
                                url: now.artworkURL,
                                size: artSide,
                                corner: 28,
                                placeholderScale: 0.18
                            )
                            .shadow(color: .black.opacity(0.3), radius: 26, y: 14)
                            .accessibilityHidden(true)

                            trackInfo(now)
                            scrubber(now)
                            transport(now)
                            lyricsButton
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, proxy.size.height - 48))
                    }
                    .scrollIndicators(.hidden)
                }
                .sheet(isPresented: $showLyrics) {
                    LyricsSheet(now: now)
                        .environment(theme)
                        .environment(player)
                }
            } else {
                idlePlayer
            }
        }
    }

    private var idlePlayer: some View {
        VStack(spacing: 0) {
            HStack {
                dismissButton
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

    private func playerHeader(_ now: PlayerStore.Now) -> some View {
        HStack {
            dismissButton

            Spacer()
            Text(sourceLabel(now.source))
                .font(Typography.medium(12))
                .foregroundStyle(theme.palette.textMuted)
                .lineLimit(1)
            Spacer()
            DeviceButton(source: now.source, size: 20)
        }
    }

    private var dismissButton: some View {
        HeartableNavigationButton(
            kind: .dismiss,
            accessibilityLabel: "Dismiss player",
            action: dismiss.callAsFunction
        )
    }

    private func trackInfo(_ now: PlayerStore.Now) -> some View {
        VStack(spacing: 6) {
            Text(now.name).font(Typography.heading(24))
                .foregroundStyle(theme.palette.text)
                .multilineTextAlignment(.center).lineLimit(2)
            Text(now.artist).font(Typography.body(16))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Visualizer(isPlaying: now.isPlaying)
                .frame(height: 20)
                .frame(maxWidth: 120)
        }
        .accessibilityElement(children: .combine)
    }

    private var lyricsButton: some View {
        Button { showLyrics = true } label: {
            Label("Lyrics", systemImage: "text.quote")
                .font(Typography.medium(13))
                .foregroundStyle(theme.palette.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(
                    Capsule().fill(theme.palette.surface)
                )
        }
        .buttonStyle(.plain)
    }

    private func scrubber(_ now: PlayerStore.Now) -> some View {
        // Live radio / unknown length: render a quiet, non-interactive idle bar.
        let hasDuration = now.durationMs > 0
        let livePct = hasDuration ? min(1, Double(now.positionMs) / Double(now.durationMs)) : 0
        // While dragging, follow the local fraction so the live poll can't fight it.
        let fraction = isScrubbing ? scrubFraction : livePct
        let displayedMs = isScrubbing ? Int(fraction * Double(now.durationMs)) : now.positionMs
        let remainingMs = max(0, now.durationMs - displayedMs)

        return VStack(spacing: 4) {
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
            HStack {
                Text(timeString(displayedMs)).font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                Spacer()
                Button {
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
    private func transport(_ now: PlayerStore.Now) -> some View {
        HStack(spacing: 0) {
            PlaybackModeControl(size: 22)
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                control("backward.fill", label: "Previous track", size: 26) {
                    Task { await player.prev() }
                }
                playButton(now)
                control("forward.fill", label: "Next track", size: 26) {
                    Task { await player.next() }
                }
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// Clean, minimal primary play/pause control: a solid disc with the glyph
    /// knocked out in the background color. Replaces the heavy filled-circle symbol.
    private func playButton(_ now: PlayerStore.Now) -> some View {
        Button { Task { await player.toggle() } } label: {
            ZStack {
                Circle().fill(theme.palette.text).frame(width: 68, height: 68)
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
    }

    private func sourceLabel(_ id: ProviderID) -> String {
        ProviderCatalog.entry(id)?.label.uppercased() ?? id.rawValue.uppercased()
    }

    private func timeString(_ ms: Int) -> String {
        let s = max(0, ms / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Lyrics panel presented from the full player. Shows synced lines (with the
/// active line highlighted in `rose`) when available, plain text as a fallback,
/// otherwise a quiet placeholder.
private struct LyricsSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss

    let now: PlayerStore.Now
    @State private var model = LyricsModel()

    private var positionMs: Int { player.now?.positionMs ?? now.positionMs }

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
        .onAppear { model.load(for: now) }
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
                    ForEach(Array(model.synced.enumerated()), id: \.element.id) { pair in
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
