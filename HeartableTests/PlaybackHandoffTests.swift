import XCTest
@testable import Heartable

@MainActor
final class PlaybackHandoffTests: XCTestCase {
    func testPendingChoiceWinsOverOldPlayingProvider() {
        let old = now(.apple, playing: true)
        let target = now(.spotify, playing: false)
        let selected = PlayerStore.selectCandidate([old, target], preferredTrack: track(.spotify),
                                                   changedAt: [.apple: Date().addingTimeInterval(1)])
        XCTAssertEqual(selected, target)
        XCTAssertFalse(selected?.isPlaying ?? true, "A pending start must not fabricate playback")
    }

    func testNoPendingChoiceStillDiscoversExternalPlayback() {
        let playing = now(.spotify, playing: true)
        XCTAssertEqual(PlayerStore.selectCandidate([now(.apple, playing: false), playing],
                                                   preferredTrack: nil, changedAt: [:]), playing)
    }

    func testPendingChoiceMatchesTrackNotJustProvider() {
        var old = now(.spotify, playing: true)
        old.uri = "spotify:track:old"
        let target = now(.spotify, playing: false)
        XCTAssertEqual(PlayerStore.selectCandidate([old, target], preferredTrack: track(.spotify),
                                                   changedAt: [:]), target)
    }

    func testConnectWaitsForNewDeviceWithoutWakingAgain() async throws {
        var calls = 0
        try await PlaybackStartupRetry.waitForSpotifyDevice(delay: .zero) {
            calls += 1
            if calls < 3 { throw NoActiveDeviceError() }
        }
        XCTAssertEqual(calls, 3)
    }

    func testConnectPropagationRetryIsBounded() async {
        var calls = 0
        do {
            try await PlaybackStartupRetry.waitForSpotifyDevice(attempts: 3, delay: .zero) {
                calls += 1
                throw NoActiveDeviceError()
            }
            XCTFail("Missing device must eventually surface")
        } catch { XCTAssertTrue(error is NoActiveDeviceError) }
        XCTAssertEqual(calls, 3)
    }

    func testConnectDoesNotRetryPermissionsFailures() async {
        var calls = 0
        do {
            try await PlaybackStartupRetry.waitForSpotifyDevice(delay: .zero) {
                calls += 1
                throw ProviderError("Reconnect Spotify")
            }
            XCTFail("Expected authorization failure")
        } catch { XCTAssertEqual(error.localizedDescription, "Reconnect Spotify") }
        XCTAssertEqual(calls, 1)
    }

    func testCancellationStopsPropagationRetries() async {
        var calls = 0
        let task = Task {
            try await PlaybackStartupRetry.waitForSpotifyDevice {
                calls += 1
                throw NoActiveDeviceError()
            }
        }
        while calls == 0 { await Task.yield() }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 1)
    }

    func testInvalidDirectStreamFailsInsteadOfClaimingSuccess() async {
        let engine = LocalAudioEngine.shared
        defer { engine.stop() }
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try await engine.play(meta, url: missing)
            XCTFail("An unreadable stream cannot start")
        } catch {
            XCTAssertFalse(engine.isPlaying)
            XCTAssertFalse(error.localizedDescription.contains(missing.path))
        }
    }

    func testCancelledDirectStartNeverInstallsTrack() async {
        let engine = LocalAudioEngine.shared
        engine.stop()
        let metadata = meta
        let task = Task {
            try await engine.play(metadata, url: URL(fileURLWithPath: "/missing.wav"))
        }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(engine.nowPlaying)
        XCTAssertFalse(engine.isPlaying)
    }

    private var meta: LocalAudioEngine.NowPlaying {
        .init(key: "fixture", providerID: .audius, uri: "audius:fixture", trackID: "fixture",
              name: "Fixture", artist: "Fixture", artworkURL: nil, durationMs: 1000)
    }

    private func track(_ provider: ProviderID) -> UnifiedTrack {
        .init(key: trackKey(provider, "new"), providerID: provider, providerTrackID: "new",
              uri: "\(provider.rawValue):track:new", name: "Song", artists: [],
              album: nil, albumArt: nil, durationMs: 180_000)
    }

    private func now(_ provider: ProviderID, playing: Bool) -> PlayerStore.Now {
        .init(source: provider, name: "Song", artist: "Artist", artworkURL: nil,
              isPlaying: playing, positionMs: 0, durationMs: 180_000,
              uri: track(provider).uri, providerTrackID: "new")
    }
}
