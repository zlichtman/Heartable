import XCTest
import Observation
import UIKit
import SwiftUI
@testable import Heartable

/// Build 95: fewer main-thread SwiftUI invalidations on iOS 26, and inputs a
/// server controls can no longer trap.
final class Build95RegressionTests: XCTestCase {

    // MARK: Retry-After

    func testRetryAfterRejectsNonFiniteAndClampsServerValues() {
        XCTAssertNil(RetryAfter.seconds("nan"))
        XCTAssertNil(RetryAfter.seconds("inf"))
        XCTAssertNil(RetryAfter.seconds("1e400"), "Double(\"1e400\") is +infinity")
        XCTAssertNil(RetryAfter.seconds(nil))
        XCTAssertEqual(RetryAfter.seconds("-5"), 0)
        XCTAssertEqual(RetryAfter.seconds(" 42 "), 42)
        XCTAssertEqual(RetryAfter.seconds("99999999999999999999"), RetryAfter.maximum)
        XCTAssertEqual(RetryAfter.seconds("120", cap: 30), 30)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(RetryAfter.seconds("Fri, 01 Jan 2100 00:00:00 GMT", now: now), RetryAfter.maximum)
        XCTAssertEqual(RetryAfter.seconds("Thu, 01 Jan 1970 00:00:00 GMT", now: now), 0)
    }

    func testSpotifyCooldownIsBoundedWhenRecordedAndWhenRestored() async throws {
        let suite = "heartable.tests.backoff.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let backoff = SpotifyReadBackoff(persisting: true, suiteName: suite)
        let delay = await backoff.record("1e400")
        XCTAssertEqual(delay, 30, accuracy: 1, "An unreadable header falls back to 30 s")
        let long = await backoff.record("9999999999")
        XCTAssertLessThanOrEqual(long, RetryAfter.maximum + 1)
        // Every consumer converts the remaining time with Int(...).
        let maybeRemaining = await backoff.remaining()
        let remaining = try XCTUnwrap(maybeRemaining)
        XCTAssertLessThan(Int(remaining), Int.max)
        XCTAssertTrue(SpotifyPlaylistFailure.message(for: SpotifyReadBackoff.Limited(retryAfter: remaining))
            .contains("minutes"))

        // A value persisted by an older build without the cap is ignored.
        UserDefaults(suiteName: suite)?.set(Date().timeIntervalSince1970 + 1e12, forKey: SpotifyReadBackoff.storeKey)
        let restored = SpotifyReadBackoff(persisting: true, suiteName: suite)
        let restoredRemaining = await restored.remaining()
        XCTAssertNil(restoredRemaining)
    }

    // MARK: Lyrics

    func testMalformedLRCTimestampsAreSkippedInsteadOfTrapping() {
        let raw = """
        [01:.]empty seconds
        [:]no fields
        [99999999999999999999:00]overflowing minutes
        [00:99999999999999999999]overflowing seconds
        [01:02.]trailing dot
        [00:05.5]half second
        [00:01.123456]long fraction
        """
        let lines = LyricsService.parseLRC(raw)
        XCTAssertEqual(lines.map(\.text), ["long fraction", "half second", "trailing dot"])
        XCTAssertEqual(lines.map(\.timeMs), [1_123, 5_500, 62_000])
    }

    // MARK: Identity

    func testHeartableTopTracksNeverRepeatARowIdentity() {
        let local = UnifiedTrack(key: "spotify:215", providerID: .spotify, providerTrackID: "215",
                                 uri: "spotify:local:A:B:One:215", name: "One", artists: [], album: nil,
                                 albumArt: nil, durationMs: 215_000)
        let other = UnifiedTrack(key: "spotify:215", providerID: .spotify, providerTrackID: "215",
                             uri: "spotify:local:C:D:Two:215", name: "Two", artists: [], album: nil,
                             albumArt: nil, durationMs: 215_000)
        let unique = TopTracksRepository.uniqueTracks([local, other, local])
        XCTAssertEqual(unique.map(\.name), ["One"])
    }

    func testTabBarStaysExpandedWhereTheAccessoryIsRehosted() {
        XCTAssertFalse(PlaylistChromePolicy.allowsMinimizing(playlistVisible: false, hasNowPlaying: true,
                                                             systemSupportsStableAccessory: false))
        XCTAssertTrue(PlaylistChromePolicy.allowsMinimizing(playlistVisible: false, hasNowPlaying: true,
                                                            systemSupportsStableAccessory: true))
        XCTAssertFalse(PlaylistChromePolicy.allowsMinimizing(playlistVisible: true, hasNowPlaying: true,
                                                             systemSupportsStableAccessory: true))
    }

    // MARK: Observation pressure

    @MainActor
    func testRepeatedPlaylistVisibilityCallbacksDoNotNotifyTheShell() {
        let first = UUID(), second = UUID()
        defer {
            PlaylistRotation.setVisible(false, id: first)
            PlaylistRotation.setVisible(false, id: second)
        }
        PlaylistRotation.setVisible(true, id: first)
        let probe = ObservationProbe()
        withObservationTracking {
            _ = PlaylistRotation.hasVisiblePlaylist
        } onChange: {
            probe.record()
        }
        // Same playlist again, a second visible playlist, then one of two hides:
        // visibility never changes, so the TabView must not be invalidated.
        PlaylistRotation.setVisible(true, id: first)
        PlaylistRotation.setVisible(true, id: second)
        PlaylistRotation.setVisible(false, id: first)
        XCTAssertTrue(PlaylistRotation.hasVisiblePlaylist)
        XCTAssertFalse(probe.fired, "An unchanged playlist visibility must not invalidate the TabView")
        // A real transition still notifies.
        PlaylistRotation.setVisible(false, id: second)
        XCTAssertTrue(probe.fired)
    }

    @MainActor
    func testPlayerSummaryIgnoresRepeatedEqualStates() async throws {
        guard !SpotifyAuth.isSignedIn else { throw XCTSkip("Requires the isolated, signed-out simulator") }
        let player = PlayerStore()
        defer { player.reset() }
        let track = UnifiedTrack(key: "spotify:fixture95", providerID: .spotify, providerTrackID: "fixture95",
                                 uri: "spotify:track:fixture95", name: "Fixture", artists: [.init(id: "a", name: "Artist")],
                                 album: "Album", albumArt: nil, durationMs: 180_000)
        await player.play(track)
        let summary = try XCTUnwrap(player.nowSummary)
        XCTAssertEqual(summary.uri, track.uri)
        XCTAssertEqual(summary.positionMs, 0, "The summary never carries a playback position")
        XCTAssertEqual(player.now?.uri, track.uri)

        let probe = ObservationProbe()
        withObservationTracking {
            _ = player.nowSummary
        } onChange: {
            probe.record()
        }
        // The same paused selection again: `now` is reassigned, the summary is not.
        await player.play(track)
        XCTAssertEqual(player.nowSummary, summary)
        XCTAssertFalse(probe.fired, "Reassigning an equal player state must not invalidate the shell")
    }

    // MARK: Rate-limited indexing

    @MainActor
    func testSpotifyCooldownSkipsSpotifyPlaylistsWithoutChurningState() async {
        let spotify = UnifiedPlaylist(key: "spotify:cool", providerID: .spotify, playlistID: "cool", name: "Cool",
                                      description: nil, image: nil, trackCount: 2, owner: nil, contentRevision: "v1")
        let apple = UnifiedPlaylist(key: "apple:warm", providerID: .apple, playlistID: "warm", name: "Warm",
                                    description: nil, image: nil, trackCount: 1, owner: nil, contentRevision: "v1")
        let fetched = FetchLog()
        let track = UnifiedTrack(key: "apple:1", providerID: .apple, providerTrackID: "1", uri: "apple:song:1",
                                 name: "Song", artists: [], album: nil, albumArt: nil, durationMs: 1_000)
        let repository = PlaylistTracksRepository(
            fetch: { playlist in
                await fetched.append(playlist.key)
                return .success([track])
            },
            persistenceEnabled: false,
            spotifyCooldownActive: { true }
        )
        await repository.synchronize([spotify, apple])
        let keys = await fetched.keys
        XCTAssertEqual(keys, ["apple:warm"], "No Spotify read is attempted during its cooldown")
        XCTAssertFalse(repository.didFail(spotify), "A skipped playlist is not recorded as a failure")
        XCTAssertFalse(repository.hasResolvedAll([spotify, apple]), "Skipped work stays pending for the next pass")
    }

    // MARK: Photos

    func testPhotoDownscaleBoundsTheLongestEdgeWithoutUpscaling() throws {
        let large = try XCTUnwrap(Self.jpeg(width: 4_032, height: 3_024))
        let scaled = try XCTUnwrap(ImageDownscale.jpeg(from: large))
        let image = try XCTUnwrap(UIImage(data: scaled))
        XCTAssertEqual(max(image.size.width * image.scale, image.size.height * image.scale), 1_024, accuracy: 1)

        let small = try XCTUnwrap(Self.jpeg(width: 320, height: 200))
        let kept = try XCTUnwrap(UIImage(data: try XCTUnwrap(ImageDownscale.jpeg(from: small))))
        XCTAssertEqual(kept.size.width * kept.scale, 320, accuracy: 1)
        XCTAssertNil(ImageDownscale.jpeg(from: Data("not an image".utf8)))
    }

    private static func jpeg(width: CGFloat, height: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}

/// Records an Observation change without failing from inside the callback, so a
/// test's own cleanup cannot be mistaken for the behavior under test.
private final class ObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var didFire = false
    var fired: Bool { lock.withLock { didFire } }
    func record() { lock.withLock { didFire = true } }
}

private actor FetchLog {
    private(set) var keys: [String] = []
    func append(_ key: String) { keys.append(key) }
}

final class DrawerDetentHysteresisTests: XCTestCase {
    @MainActor
    func testDrawerGrowsImmediatelyButIgnoresSmallShrinks() {
        typealias Drawer = HeartableDrawer<EmptyView>
        XCTAssertEqual(Drawer.detentHeight(current: 240, measured: 612), 612)
        XCTAssertNil(Drawer.detentHeight(current: 612, measured: 612.5))
        // A two-value oscillation near the screen height (one wrapped line)
        // must not keep resizing the sheet.
        XCTAssertNil(Drawer.detentHeight(current: 860, measured: 840))
        XCTAssertEqual(Drawer.detentHeight(current: 860, measured: 600), 600)
        XCTAssertNil(Drawer.detentHeight(current: 240, measured: .nan))
        XCTAssertNil(Drawer.detentHeight(current: 240, measured: 0))
        // The placeholder never leaves a short drawer with empty space.
        XCTAssertEqual(Drawer.detentHeight(current: 240, measured: 220, hasMeasured: false), 220)
    }
}
