import XCTest
@testable import Heartable

final class AudioSettingsTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) rethrows {
        let suite = "heartable.audio.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }

    func testFreshDefaultsKeepThePreviousPlaybackLevel() {
        withDefaults { defaults in
            let settings = AudioSettings.current(defaults)
            XCTAssertFalse(settings.crossfade)
            XCTAssertEqual(settings.volume, 0.82)
            XCTAssertEqual(settings.crossfadeDuration, 2)
        }
    }

    func testMigrationPreservesLegacyTrimAndCrossfade() {
        withDefaults { defaults in
            defaults.set(true, forKey: AudioSettings.Key.legacyNormalize)
            defaults.set(true, forKey: AudioSettings.Key.crossfade)
            XCTAssertEqual(AudioSettings.current(defaults).volume, 0.82)
            XCTAssertTrue(AudioSettings.current(defaults).crossfade)
        }
    }

    func testMigrationPreservesLegacyFullVolume() {
        withDefaults { defaults in
            defaults.set(false, forKey: AudioSettings.Key.legacyNormalize)
            XCTAssertEqual(AudioSettings.current(defaults).volume, 1)
        }
    }

    func testNewVolumeAndDurationOverrideLegacyValues() {
        withDefaults { defaults in
            defaults.set(true, forKey: AudioSettings.Key.legacyNormalize)
            defaults.set(0.35, forKey: AudioSettings.Key.volume)
            defaults.set(6, forKey: AudioSettings.Key.crossfadeDuration)
            XCTAssertEqual(AudioSettings.current(defaults).volume, 0.35)
            XCTAssertEqual(AudioSettings.current(defaults).crossfadeDuration, 6)
        }
    }

    func testZeroVolumeIsMuteNotAnUnsetPreference() {
        withDefaults { defaults in
            defaults.set(0, forKey: AudioSettings.Key.volume)
            XCTAssertEqual(AudioSettings.current(defaults).targetVolume, 0)
        }
    }

    func testOutOfRangePreferencesAreClamped() {
        let low = AudioSettings(crossfade: true, volume: -2, crossfadeDuration: -1)
        let high = AudioSettings(crossfade: true, volume: 5, crossfadeDuration: 100)
        XCTAssertEqual(low.volume, 0)
        XCTAssertEqual(low.crossfadeDuration, 1)
        XCTAssertEqual(high.volume, 1)
        XCTAssertEqual(high.crossfadeDuration, 8)
    }

    func testNonfinitePreferencesHaveSafeDefaults() {
        for value in [Double.nan, .infinity, -.infinity] {
            let settings = AudioSettings(crossfade: true, volume: value, crossfadeDuration: value)
            XCTAssertEqual(settings.volume, AudioSettings.defaultVolume)
            XCTAssertEqual(settings.crossfadeDuration, AudioSettings.defaultCrossfadeDuration)
        }
    }

    func testCrossfadeGainsTrackTheCurrentVolume() {
        let loud = AudioSettings(crossfade: true, volume: 0.8).fadeVolumes(progress: 0.25)
        let quiet = AudioSettings(crossfade: true, volume: 0.4).fadeVolumes(progress: 0.25)
        XCTAssertEqual(loud.incoming, 0.2, accuracy: 0.0001)
        XCTAssertEqual(loud.outgoing, 0.6, accuracy: 0.0001)
        XCTAssertEqual(quiet.incoming, 0.1, accuracy: 0.0001)
        XCTAssertEqual(quiet.outgoing, 0.3, accuracy: 0.0001)
    }

    func testCrossfadeEndpointsAndMuteDoNotLeakTheOutgoingTrack() {
        let settings = AudioSettings(crossfade: true, volume: 0.8)
        XCTAssertEqual(settings.fadeVolumes(progress: 0).incoming, 0)
        XCTAssertEqual(settings.fadeVolumes(progress: 1).outgoing, 0)
        XCTAssertEqual(settings.fadeVolumes(progress: .nan).incoming, settings.targetVolume)
        XCTAssertEqual(settings.fadeVolumes(progress: -1).outgoing, settings.targetVolume)
        let muted = AudioSettings(crossfade: true, volume: 0).fadeVolumes(progress: 0.5)
        XCTAssertEqual(muted.incoming, 0)
        XCTAssertEqual(muted.outgoing, 0)
    }
}
