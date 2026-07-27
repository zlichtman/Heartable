import Foundation

/// Reads the in-app audio preferences set in `SoundsView` straight from the same
/// `@AppStorage` (UserDefaults) keys, so `LocalAudioEngine` and the settings UI
/// stay in sync without an injected store. These prefs only affect audio Heartable
/// streams itself (Audius full tracks, Deezer 30s previews) — Spotify and Apple
/// Music play through their own apps and can't be processed here.
///
/// A plain `Sendable` snapshot read on demand (UserDefaults reads are cheap and the
/// values change rarely), so there's nothing to inject into the environment.
struct AudioSettings: Sendable, Equatable {
    /// Whether to fade the outgoing track down and the incoming track up at a
    /// track change. Genuinely applied by the engine.
    var crossfade: Bool
    /// A conservative loudness trim (NOT full ReplayGain) applied via player
    /// volume so in-app tracks don't jump out louder than the rest of the system.
    var normalize: Bool

    /// Crossfade duration. Matches the "2s overlap" copy in `SoundsView`.
    static let crossfadeDuration: TimeInterval = 2.0

    /// Target player volume when `normalize` is on. A modest, fixed trim that
    /// evens out the worst loudness jumps without measuring per-track gain.
    static let normalizedVolume: Float = 0.82
    static let fullVolume: Float = 1.0

    /// AppStorage / UserDefaults keys, shared with `SoundsView`.
    enum Key {
        static let crossfade = "heartable.sounds.crossfade"
        static let normalize = "heartable.sounds.normalize"
    }

    /// Snapshot the current preferences from `UserDefaults`.
    static func current(_ defaults: UserDefaults = .standard) -> AudioSettings {
        // `normalize` defaults to true in the UI; mirror that when the key is unset.
        let normalize = defaults.object(forKey: Key.normalize) == nil
            ? true
            : defaults.bool(forKey: Key.normalize)
        return AudioSettings(
            crossfade: defaults.bool(forKey: Key.crossfade),
            normalize: normalize
        )
    }

    /// The volume the engine should target for a freshly-started track given the
    /// current normalization preference.
    var targetVolume: Float { normalize ? Self.normalizedVolume : Self.fullVolume }
}
