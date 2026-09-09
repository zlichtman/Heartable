import XCTest
@testable import Heartable

final class ProviderCatalogTests: XCTestCase {
    func testCatalogContainsEachConnectableProviderOnce() {
        let ids = ProviderCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.contains(.heartable))
    }

    func testPlaybackCapabilityMatchesPlaybackTier() {
        for entry in ProviderCatalog.all where entry.status == .live {
            XCTAssertEqual(
                entry.capabilities.contains(.playback),
                entry.playbackTier != .none,
                "\(entry.label) has inconsistent playback metadata"
            )
        }
    }

    func testLocalAudioProvidersArePlayable() {
        for entry in ProviderCatalog.all where entry.usesLocalAudioEngine {
            XCTAssertNotEqual(entry.playbackTier, .none, "\(entry.label) has no playable source")
        }
    }

    func testAppleDoesNotClaimPersonalTopTrackCapability() {
        XCTAssertFalse(
            ProviderCatalog.entry(.apple)?.capabilities.contains(.top) ?? true
        )
    }

    func testProviderRankingDeduplicatesOnlyStableTrackKeys() {
        let first = track(.spotify, "same")
        let duplicate = track(.spotify, "same")
        let differentRecording = track(.spotify, "different")

        let unique = TopTracksRepository.uniqueTracks([
            first, duplicate, differentRecording,
        ])

        XCTAssertEqual(unique.map(\.key), [first.key, differentRecording.key])
    }

    func testStatsSourcesOnlyExposeServicesWithValidRankings() {
        XCTAssertEqual(
            TopTracksSource.selectableSources(connectedProviderIDs: []),
            [.heartable]
        )
        XCTAssertEqual(
            TopTracksSource.selectableSources(
                connectedProviderIDs: [.spotify, .apple]
            ),
            [.heartable, .spotify]
        )
        XCTAssertFalse(TopTracksSource.apple.providesTopTracks)
        XCTAssertTrue(TopTracksSource.spotify.providesTopTracks)
    }

    func testAppleTopTracksNeverSubstitutesLibraryOrCatalogRows() async {
        let tracks = await AppleMusicProvider().topTracks(
            range: .shortTerm,
            limit: 25
        )

        XCTAssertTrue(tracks.isEmpty)
    }

    func testPersonalStatsNeverInventTracksWithoutPlayEvents() {
        let stats = TopTracksRepository.aggregate(
            entries: [],
            range: .longTerm,
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )

        XCTAssertTrue(stats.isEmpty)
    }

    func testPersonalStatsRankByObservedPlayCountNotProviderOrder() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let spotify = (0..<5).map {
            play(
                uri: "spotify:track:s\($0)",
                title: "Actually Played",
                artist: "Artist",
                date: now.addingTimeInterval(TimeInterval(-$0))
            )
        }
        let apple = [
            play(
                uri: "apple:track:a1",
                title: "Saved Apple Album",
                artist: "Other",
                date: now
            ),
        ]

        let stats = TopTracksRepository.aggregate(
            entries: spotify + apple,
            range: .longTerm,
            now: now
        )

        XCTAssertEqual(stats.map(\.plays), [5, 1])
        XCTAssertEqual(stats.first?.track.name, "Actually Played")
    }

    func testPersonalStatsCollapseTheSameSongAcrossProviders() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let entries = [
            play(uri: "spotify:track:s1", title: "One Song", artist: "Artist", date: now),
            play(uri: "apple:track:a1", title: "One Song", artist: "Artist", date: now),
        ]

        let stats = TopTracksRepository.aggregate(
            entries: entries,
            range: .longTerm,
            now: now
        )

        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.first?.plays, 2)
    }

    func testPersonalStatsRespectListeningWindows() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let entries = [
            play(uri: "spotify:track:new", title: "New", artist: "Artist",
                 date: now.addingTimeInterval(-27 * 86_400)),
            play(uri: "spotify:track:old", title: "Old", artist: "Artist",
                 date: now.addingTimeInterval(-29 * 86_400)),
        ]

        let short = TopTracksRepository.aggregate(
            entries: entries,
            range: .shortTerm,
            now: now
        )
        let all = TopTracksRepository.aggregate(
            entries: entries,
            range: .longTerm,
            now: now
        )

        XCTAssertEqual(short.map(\.track.name), ["New"])
        XCTAssertEqual(Set(all.map(\.track.name)), ["New", "Old"])
    }

    func testGhostModeSuppressesTheWholePlaybackSession() {
        var tracker = ListeningSessionTracker()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var current = now(uri: "spotify:track:ghost", playing: true, positionMs: 0)

        for tick in 0...7 {
            current.positionMs = tick * 5_000
            XCTAssertFalse(
                tracker.observe(
                    now: current,
                    ghost: true,
                    at: start.addingTimeInterval(TimeInterval(tick * 5))
                )
            )
        }

        XCTAssertFalse(
            tracker.observe(
                now: current,
                ghost: false,
                at: start.addingTimeInterval(40)
            )
        )
    }

    func testStoppingThenRestartingTheSameURIStartsANewQualifiedListen() {
        var tracker = ListeningSessionTracker()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var current = now(uri: "spotify:track:repeat", playing: true, positionMs: 0)

        for tick in 0...6 {
            current.positionMs = tick * 5_000
            _ = tracker.observe(
                now: current,
                ghost: false,
                at: start.addingTimeInterval(TimeInterval(tick * 5))
            )
        }
        XCTAssertTrue(
            tracker.observe(
                now: current,
                ghost: false,
                at: start.addingTimeInterval(35)
            )
        )
        tracker.markLogged()
        XCTAssertFalse(
            tracker.observe(
                now: nil,
                ghost: false,
                at: start.addingTimeInterval(36)
            )
        )

        current.positionMs = 0
        XCTAssertFalse(
            tracker.observe(
                now: current,
                ghost: false,
                at: start.addingTimeInterval(40)
            )
        )
        for tick in 1...5 {
            current.positionMs = tick * 5_000
            _ = tracker.observe(
                now: current,
                ghost: false,
                at: start.addingTimeInterval(TimeInterval(40 + tick * 5))
            )
        }
        current.positionMs = 30_000
        XCTAssertTrue(
            tracker.observe(
                now: current,
                ghost: false,
                at: start.addingTimeInterval(70)
            )
        )
    }

    private func track(_ provider: ProviderID, _ id: String) -> UnifiedTrack {
        UnifiedTrack(
            key: trackKey(provider, id),
            providerID: provider,
            providerTrackID: id,
            uri: "\(provider.rawValue):track:\(id)",
            name: id,
            artists: [],
            album: nil,
            albumArt: nil,
            durationMs: 0
        )
    }

    private func play(
        uri: String,
        title: String,
        artist: String,
        date: Date
    ) -> PlayEntryDTO {
        PlayEntryDTO(
            id: UUID(),
            trackUri: uri,
            trackName: title,
            artist: artist,
            durationMs: 180_000,
            playedAt: ISO8601DateFormatter().string(from: date),
            albumArt: nil
        )
    }

    private func now(
        uri: String,
        playing: Bool,
        positionMs: Int
    ) -> PlayerStore.Now {
        PlayerStore.Now(
            source: .spotify,
            name: "Track",
            artist: "Artist",
            artworkURL: nil,
            isPlaying: playing,
            positionMs: positionMs,
            durationMs: 180_000,
            uri: uri,
            providerTrackID: String(uri.split(separator: ":").last ?? "")
        )
    }
}
