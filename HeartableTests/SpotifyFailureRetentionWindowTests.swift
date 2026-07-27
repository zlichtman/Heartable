import XCTest
@testable import Heartable

final class SpotifyFailureRetentionWindowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    func testRepeatedFailuresDoNotExtendGraceWindow() {
        var window = SpotifyFailureRetentionWindow()

        XCTAssertTrue(window.shouldRetain(at: start, grace: 30))
        XCTAssertTrue(
            window.shouldRetain(
                at: start.addingTimeInterval(29),
                grace: 30
            )
        )
        XCTAssertFalse(
            window.shouldRetain(
                at: start.addingTimeInterval(30),
                grace: 30
            )
        )
        XCTAssertFalse(
            window.shouldRetain(
                at: start.addingTimeInterval(60),
                grace: 30
            )
        )
    }

    func testSuccessfulPollResetsGraceWindow() {
        var window = SpotifyFailureRetentionWindow()

        XCTAssertTrue(window.shouldRetain(at: start, grace: 30))
        XCTAssertFalse(
            window.shouldRetain(
                at: start.addingTimeInterval(31),
                grace: 30
            )
        )

        window.reset()

        XCTAssertTrue(
            window.shouldRetain(
                at: start.addingTimeInterval(31),
                grace: 30
            )
        )
    }

    func testRateLimitCanExtendGraceThroughNextAllowedPoll() {
        var window = SpotifyFailureRetentionWindow()
        let retryDate = start.addingTimeInterval(120)

        window.extend(through: retryDate)

        XCTAssertTrue(
            window.shouldRetain(
                at: start.addingTimeInterval(119),
                grace: 30
            )
        )
        XCTAssertFalse(
            window.shouldRetain(
                at: retryDate,
                grace: 30
            )
        )
    }

    func testPlaybackFallbackRequiresExactSongIdentity() {
        let original = track(
            provider: .spotify,
            id: "spotify",
            name: "Midnight City",
            artist: "M83",
            durationMs: 244_000
        )
        let wrongSong = track(
            provider: .audius,
            id: "wrong",
            name: "Midnight",
            artist: "M83",
            durationMs: 244_000
        )

        XCTAssertNil(
            PlaybackFallbackSelector.bestAlternative(
                for: original,
                from: [wrongSong]
            )
        )
    }

    func testPlaybackFallbackPrefersFullInAppPlaybackOverPreview() {
        let original = track(
            provider: .spotify,
            id: "spotify",
            name: "Midnight City",
            artist: "M83",
            durationMs: 244_000
        )
        let preview = track(
            provider: .deezer,
            id: "preview",
            name: "Midnight City",
            artist: "M83",
            durationMs: 244_000
        )
        let full = track(
            provider: .audius,
            id: "full",
            name: "Midnight City",
            artist: "M83",
            durationMs: 246_000
        )

        XCTAssertEqual(
            PlaybackFallbackSelector.bestAlternative(
                for: original,
                from: [preview, full]
            )?.providerID,
            .audius
        )
    }

    func testPlaybackFallbackRejectsAnotherSpotifyResult() {
        let original = track(
            provider: .spotify,
            id: "spotify",
            name: "Midnight City",
            artist: "M83",
            durationMs: 244_000
        )
        let spotifyResult = track(
            provider: .spotify,
            id: "other",
            name: "Midnight City",
            artist: "M83",
            durationMs: 244_000
        )

        XCTAssertNil(
            PlaybackFallbackSelector.bestAlternative(
                for: original,
                from: [spotifyResult]
            )
        )
    }

    private func track(
        provider: ProviderID,
        id: String,
        name: String,
        artist: String,
        durationMs: Int
    ) -> UnifiedTrack {
        UnifiedTrack(
            key: trackKey(provider, id),
            providerID: provider,
            providerTrackID: id,
            uri: "\(provider.rawValue):track:\(id)",
            name: name,
            artists: [UnifiedArtist(id: artist, name: artist)],
            album: nil,
            albumArt: nil,
            durationMs: durationMs
        )
    }
}
