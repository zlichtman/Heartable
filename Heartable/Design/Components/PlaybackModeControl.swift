import SwiftUI

/// Playback order or ordinary shuffle, shared by library and player controls.
struct PlaybackModeControl: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlaybackPrefsStore.self) private var prefs
    @State private var showingModes = false

    /// Glyph point size. The tappable target grows with it. Defaults suit the full
    /// player transport row; the mini player passes a smaller value.
    var size: CGFloat = 22

    /// Whether a non-order mode is currently active (drives the rose emphasis).
    private var isActive: Bool { prefs.mode != .order }

    var body: some View {
        Button {
            showingModes = true
        } label: {
            glyph
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback mode")
        .accessibilityValue(prefs.mode.label)
        .sheet(isPresented: $showingModes) {
            HeartableChoiceSheet(
                title: "Playback mode",
                items: ShuffleMode.allCases.map { mode in
                    HeartableChoiceItem(
                        id: mode.rawValue,
                        icon: mode.symbol,
                        title: mode.label,
                        subtitle: mode.caption,
                        isSelected: prefs.mode == mode
                    )
                },
                onCancel: { showingModes = false },
                onSelect: { item in
                    if let mode = ShuffleMode(rawValue: item.id) {
                        prefs.mode = mode
                    }
                    showingModes = false
                }
            )
        }
    }

    private var glyph: some View {
        let target = max(44, size + 22)
        return Image(systemName: prefs.mode.symbol)
            .font(.system(size: size * 0.68, weight: .medium))
            .foregroundStyle(isActive ? theme.palette.rose : theme.palette.textMuted)
            .frame(width: target, height: target)
            .background(
                Circle().fill(isActive ? theme.palette.rose.opacity(0.14) : .clear)
                    .frame(width: target * 0.82, height: target * 0.82)
            )
            .contentShape(Circle())
    }
}
