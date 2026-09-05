import SwiftUI

/// Real controls for direct streams. Provider-owned audio never presents a
/// pretend equalizer or normalization switch.
struct SoundsView: View {
    @Environment(ThemeStore.self) private var theme

    @AppStorage(AudioSettings.Key.volume) private var volume = AudioSettings.current().volume
    @AppStorage(AudioSettings.Key.crossfade) private var crossfade = false
    @AppStorage(AudioSettings.Key.crossfadeDuration) private var duration = AudioSettings.defaultCrossfadeDuration

    private var settings: AudioSettings {
        AudioSettings(crossfade: crossfade, volume: volume, crossfadeDuration: duration)
    }

    var body: some View {
        SettingsScaffold(title: "Sounds") {
            sectionHeader("Direct playback")
            card {
                VStack(alignment: .leading, spacing: 16) {
                    controlHeading(
                        icon: "speaker.wave.2.fill",
                        title: "Stream volume",
                        value: "\(Int((settings.volume * 100).rounded()))%"
                    )
                    Slider(value: Binding(get: { settings.volume }, set: { volume = ($0 * 100).rounded() / 100 }),
                           in: 0...1) {
                        Text("Stream volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .accessibilityValue("\(Int((settings.volume * 100).rounded())) percent")
                    .accessibilityIdentifier("sounds.volume")
                    .tint(theme.palette.rose)
                    .foregroundStyle(theme.palette.textSecondary)
                }
            }

            card {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $crossfade) {
                        HStack(spacing: 12) {
                            controlIcon("arrow.left.arrow.right")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Crossfade")
                                    .font(Typography.semibold(15))
                                    .foregroundStyle(theme.palette.text)
                                Text("Blend when switching tracks")
                                    .font(Typography.body(12))
                                    .foregroundStyle(theme.palette.textMuted)
                            }
                        }
                    }
                    .tint(theme.palette.rose)
                    .accessibilityIdentifier("sounds.crossfade")

                    if crossfade {
                        Divider().overlay(theme.palette.border)
                        HStack {
                            Text("Duration")
                                .font(Typography.medium(13))
                                .foregroundStyle(theme.palette.textSecondary)
                            Spacer()
                            valuePill("\(Int(settings.crossfadeDuration.rounded()))s")
                        }
                        Slider(value: Binding(get: { settings.crossfadeDuration }, set: { duration = $0 }),
                               in: AudioSettings.crossfadeDurationRange, step: 1) {
                            Text("Crossfade duration")
                        }
                        .tint(theme.palette.rose)
                        .accessibilityValue("\(Int(settings.crossfadeDuration.rounded())) seconds")
                        .accessibilityIdentifier("sounds.crossfadeDuration")
                        HStack {
                            Text("1s")
                            Spacer()
                            Text("8s")
                        }
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .accessibilityHidden(true)
                    }
                }
            }

            Text("For audio streamed by Heartable. Spotify and Apple Music keep their own audio settings.")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
        .onChange(of: settings, initial: true) {
            // Sanitize old or invalid defaults before feeding them to sliders.
            let current = settings
            volume = current.volume
            duration = current.crossfadeDuration
            LocalAudioEngine.shared.applySettings(current)
        }
        .sensoryFeedback(.selection, trigger: crossfade)
        .sensoryFeedback(.selection, trigger: Int(settings.crossfadeDuration.rounded()))
    }

    // MARK: - Atoms

    private func controlHeading(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            controlIcon(icon)
            Text(title)
                .font(Typography.semibold(15))
                .foregroundStyle(theme.palette.text)
            Spacer(minLength: 4)
            valuePill(value)
        }
    }

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(theme.palette.rose)
            .frame(width: 40, height: 40)
            .background(theme.palette.roseDim, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private func valuePill(_ text: String) -> some View {
        Text(text)
            .font(Typography.semibold(13))
            .monospacedDigit()
            .foregroundStyle(theme.palette.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(theme.palette.surface, in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(theme.palette.border, lineWidth: 1)
            )
    }
}
