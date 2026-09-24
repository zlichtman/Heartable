import XCTest
@testable import Heartable

final class SpotifyHistoryAndQueueTests: XCTestCase {
    func testProviderBoundaryAcceptsStoppedFinalItemButNotPauseOrNetworkFailure() throws {
        var previous = PlayerStore.Now(source: .spotify, name: "Song", artist: "Artist", artworkURL: nil,
                                       isPlaying: true, positionMs: 179_000, durationMs: 180_000,
                                       uri: "spotify:track:a", providerTrackID: "a")
        let stopped = try JSONDecoder().decode(PlaybackState.self, from: Data("""
        {"is_playing":false,"progress_ms":180000,"item":{"id":"a","uri":"spotify:track:a","name":"Song"}}
        """.utf8))
        XCTAssertTrue(SpotifyQueueOrder.didFinishSegment(previous: previous, state: stopped, wasIdle: false, elapsed: 2))
        XCTAssertFalse(SpotifyQueueOrder.didFinishSegment(previous: previous, state: nil, wasIdle: false, elapsed: 2))
        previous.positionMs = 90_000
        XCTAssertFalse(SpotifyQueueOrder.didFinishSegment(previous: previous, state: stopped, wasIdle: false, elapsed: 2))
        XCTAssertFalse(SpotifyQueueOrder.didFinishSegment(previous: previous, state: nil, wasIdle: true, elapsed: 2))
    }

    func testQueueConfirmationRequiresBothSettingsAndCorrectDevice() throws {
        func state(_ shuffle: String, _ repeatMode: String, device: String = "phone") throws -> PlaybackState {
            try JSONDecoder().decode(PlaybackState.self, from: Data("""
            {"shuffle_state":\(shuffle),"repeat_state":"\(repeatMode)","device":{"id":"\(device)","is_active":true}}
            """.utf8))
        }
        XCTAssertTrue(SpotifyQueueOrder.isConfirmed(try state("false", "off"), deviceID: "phone"))
        XCTAssertFalse(SpotifyQueueOrder.isConfirmed(try state("true", "off"), deviceID: "phone"))
        XCTAssertFalse(SpotifyQueueOrder.isConfirmed(try state("false", "context"), deviceID: "phone"))
        XCTAssertFalse(SpotifyQueueOrder.isConfirmed(try state("false", "off", device: "speaker"), deviceID: "phone"))
        XCTAssertFalse(SpotifyQueueOrder.isConfirmed(try JSONDecoder().decode(PlaybackState.self, from: Data("{}".utf8)), deviceID: nil))
        let path = SpotifyQueueOrder.controlPath("shuffle", value: "false", deviceID: "phone&speaker")
        let items = URLComponents(string: path)!.queryItems!
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.last?.value, "phone&speaker")
    }

    func testRecentlyPlayedMappingPreservesProviderTimeAndRepeats() throws {
        let data = Data("""
        {"items":[
          {"played_at":"2026-09-05T14:00:00.000Z","track":{"id":"a","uri":"spotify:track:a","name":"Song","duration_ms":180000,"artists":[{"name":"Artist"}]}},
          {"played_at":"2026-09-05T14:05:00.000Z","track":{"id":"a","uri":"spotify:track:a","name":"Song","duration_ms":180000}}
        ]}
        """.utf8)
        let plays = try JSONDecoder().decode(SpotifyRecentHistory.self, from: data).items!
        let payloads = plays.compactMap(\.payload)
        XCTAssertEqual(payloads.count, 2)
        XCTAssertNotEqual(payloads[0].playedAt, payloads[1].playedAt)
        XCTAssertEqual(payloads[0].trackUri, "spotify:track:a")
        XCTAssertEqual(payloads[0].artist, "Artist")
        XCTAssertNotNil(HistoryTimestamp.date("2026-09-05T14:00:00Z"))
        XCTAssertNil(HistoryTimestamp.date("not a date"))
    }

    func testImportedHistoryDoesNotDuplicateObservedSessionButKeepsRepeat() {
        func entry(at date: String) -> PlayEntryDTO {
            .init(id: UUID(), trackUri: "spotify:track:a", trackName: "Song", artist: "Artist",
                  durationMs: 180_000, playedAt: date, albumArt: nil)
        }
        let observed = entry(at: "2026-09-05T14:00:30Z")
        let imported = entry(at: "2026-09-05T14:00:00.000Z")
        let repeatPlay = entry(at: "2026-09-05T14:04:00Z")
        let merged = ListeningHistoryItem.merge(observed: [observed], imported: [imported, repeatPlay])
        XCTAssertEqual(merged.map(\.id), [repeatPlay.id, observed.id])
        XCTAssertTrue(merged[0].imported)
        XCTAssertFalse(merged[1].imported)
    }

    /// The queue-mode warning must say what Spotify actually reported, so a
    /// refusal, Smart Shuffle, or a device mismatch is not one vague sentence.
    func testUnconfirmedQueueModeNamesTheActualCause() throws {
        func state(_ json: String) throws -> PlaybackState {
            try JSONDecoder().decode(PlaybackState.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            SpotifyQueueOrder.describeUnconfirmed(state: nil, deviceID: nil, refusal: "Spotify refused playback: Restriction violated"),
            "Spotify refused to change the playback mode: Spotify refused playback: Restriction violated")
        let shuffled = try state(#"{"shuffle_state":true,"repeat_state":"off","device":{"id":"d1","is_active":true,"name":"iPhone"}}"#)
        XCTAssertTrue(SpotifyQueueOrder.describeUnconfirmed(state: shuffled, deviceID: "d1", refusal: nil).contains("Smart Shuffle"))
        let elsewhere = try state(#"{"shuffle_state":false,"repeat_state":"context","device":{"id":"d2","is_active":true,"name":"Kitchen"}}"#)
        let text = SpotifyQueueOrder.describeUnconfirmed(state: elsewhere, deviceID: "d1", refusal: nil)
        XCTAssertTrue(text.contains("Repeat is still context"))
        XCTAssertTrue(text.contains("Kitchen"))
        XCTAssertEqual(SpotifyQueueOrder.describeUnconfirmed(state: nil, deviceID: nil, refusal: nil),
                       "Spotify didn’t report the device state.")
    }

    /// A "restriction violated" refusal is explained with the actions Spotify
    /// itself marks as disallowed on the current device.
    func testPlaybackStateDecodesDisallowedActions() throws {
        let json = #"{"is_playing":true,"actions":{"disallows":{"resuming":true,"toggling_shuffle":true,"pausing":false}}}"#
        let state = try JSONDecoder().decode(PlaybackState.self, from: Data(json.utf8))
        XCTAssertEqual(state.actions?.disallowedActions, ["resuming", "toggling_shuffle"])
        let bare = try JSONDecoder().decode(PlaybackState.self, from: Data(#"{"is_playing":false}"#.utf8))
        XCTAssertNil(bare.actions)
    }
}
