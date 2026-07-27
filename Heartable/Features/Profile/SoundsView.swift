import SwiftUI

/// The two sound controls Heartable actually implements for audio it streams
/// itself (Audius full tracks and Deezer previews). Spotify and Apple Music own
/// their audio pipelines, so Heartable does not pretend to offer EQ/mono controls
/// it cannot apply.
struct SoundsView: View {
    @Environment(ThemeStore.self) private var theme

    @AppStorage("heartable.sounds.normalize") private var normalize = true
    @AppStorage("heartable.sounds.crossfade") private var crossfade = false

    var body: some View {
        SettingsScaffold(title: "Sounds") {
            sectionHeader("In-app playback")
            card {
                VStack(spacing: 0) {
                    toggleRow(
                        icon: "speaker.wave.2.fill",
                        label: "Consistent volume",
                        subtitle: "Reduce loudness jumps for Heartable-streamed audio",
                        isOn: $normalize
                    )
                    divider
                    toggleRow(
                        icon: "arrow.left.arrow.right",
                        label: "Crossfade",
                        subtitle: "2s overlap between songs",
                        isOn: $crossfade
                    )
                }
            }

            Text("These controls apply only to audio Heartable streams directly. Spotify and Apple Music playback remains controlled by those services.")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: - Atoms

    private func toggleRow(
        icon: String,
        label: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                }
            }
        }
        .tint(theme.palette.rose)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Divider().overlay(theme.palette.border)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
            .padding(.top, 6)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(theme.palette.border, lineWidth: 1)
            )
    }
}
