import SwiftUI

/// A lightweight animated bar visualizer. When `isPlaying`, each bar pulses its
/// height with a staggered `easeInOut.repeatForever` animation; otherwise the bars
/// rest at a low flat level. Every bar derives from the active semantic accent,
/// so the player never carries colors from a previous or unrelated preset.
struct Visualizer: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let isPlaying: Bool
    var barCount: Int = 6

    @State private var animating = false

    /// Deterministic per-bar tall fraction so the bars are uneven but stable.
    private static let peaks: [CGFloat] = [0.55, 0.95, 0.7, 1.0, 0.6, 0.85, 0.75]

    private func peak(_ i: Int) -> CGFloat { Self.peaks[i % Self.peaks.count] }

    private func tint(_ i: Int) -> Color {
        let opacity = 0.64 + (Double(i % 4) * 0.12)
        return theme.palette.rose.opacity(min(1, opacity))
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    bar(index: i, maxHeight: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
        // A repeating animation must not keep driving view updates while the
        // app is inactive or playing in the background.
        .onAppear { updateAnimating() }
        .onChange(of: isPlaying) { updateAnimating() }
        .onChange(of: reduceMotion) { updateAnimating() }
        .onChange(of: scenePhase) { updateAnimating() }
    }

    private func updateAnimating() {
        let next = isPlaying && !reduceMotion && scenePhase == .active
        if animating != next { animating = next }
    }

    private func bar(index i: Int, maxHeight: CGFloat) -> some View {
        let low = maxHeight * 0.2
        let high = maxHeight * peak(i)
        let active = isPlaying && animating
        // Animate a render-time scale, not the frame: a repeating frame change
        // re-runs layout for the whole surrounding player every display frame.
        return Capsule()
            .fill(tint(i))
            .frame(width: 3, height: high)
            .scaleEffect(x: 1, y: active || high <= 0 ? 1 : low / high, anchor: .center)
            .animation(
                active
                    ? .easeInOut(duration: 0.5 + Double(i % 3) * 0.12)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.08)
                    : .easeInOut(duration: 0.25),
                value: active
            )
    }
}
