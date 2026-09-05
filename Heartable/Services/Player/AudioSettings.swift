import Foundation

/// Device-level controls for Heartable's direct streams, not provider-owned
/// players. No normalization claim: a fixed player gain cannot measure loudness.
struct AudioSettings: Sendable, Equatable {
    let crossfade: Bool
    let volume: Double
    let crossfadeDuration: TimeInterval

    static let defaultVolume = 0.82
    static let defaultCrossfadeDuration: TimeInterval = 2
    static let crossfadeDurationRange: ClosedRange<Double> = 1...8

    enum Key {
        static let crossfade = "heartable.sounds.crossfade"
        static let volume = "heartable.sounds.volume"
        static let crossfadeDuration = "heartable.sounds.crossfadeDuration"
        /// Read-only compatibility with builds that called a fixed 82% gain
        /// "Consistent volume". Keep the same loudness on upgrade.
        static let legacyNormalize = "heartable.sounds.normalize"
    }

    init(crossfade: Bool, volume: Double, crossfadeDuration: TimeInterval = defaultCrossfadeDuration) {
        self.crossfade = crossfade
        self.volume = volume.isFinite ? min(1, max(0, volume)) : Self.defaultVolume
        self.crossfadeDuration = crossfadeDuration.isFinite
            ? min(Self.crossfadeDurationRange.upperBound,
                  max(Self.crossfadeDurationRange.lowerBound, crossfadeDuration))
            : Self.defaultCrossfadeDuration
    }

    static func current(_ defaults: UserDefaults = .standard) -> AudioSettings {
        let legacyTrim = defaults.object(forKey: Key.legacyNormalize) == nil
            || defaults.bool(forKey: Key.legacyNormalize)
        let volume = defaults.object(forKey: Key.volume) == nil
            ? (legacyTrim ? defaultVolume : 1)
            : defaults.double(forKey: Key.volume)
        let duration = defaults.object(forKey: Key.crossfadeDuration) == nil
            ? defaultCrossfadeDuration
            : defaults.double(forKey: Key.crossfadeDuration)
        return AudioSettings(
            crossfade: defaults.bool(forKey: Key.crossfade),
            volume: volume,
            crossfadeDuration: duration
        )
    }

    var targetVolume: Float { Float(volume) }

    /// Complementary gains keep changes in the volume slider live during a
    /// transition. A cancelled fade always settles at the current target gain.
    func fadeVolumes(progress: Float) -> (incoming: Float, outgoing: Float) {
        let fraction = progress.isFinite ? min(1, max(0, progress)) : 1
        return (targetVolume * fraction, targetVolume * (1 - fraction))
    }
}
