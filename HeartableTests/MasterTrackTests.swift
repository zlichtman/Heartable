import XCTest
@testable import Heartable

final class MasterTrackTests: XCTestCase {
    func testGroupingKeepsOneSourcePerProvider() {
        let spotify = track(
            provider: .spotify,
            id: "spotify-id",
            name: "Midnight City",
            artist: "M83"
        )
        let apple = track(
            provider: .apple,
            id: "apple-id",
            name: "Midnight City",
            artist: "M83"
        )

        let grouped = MasterTrack.group([spotify, apple])

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped[0].providerSet, [.spotify, .apple])
    }

    func testFullPlaybackWinsOverPreview() {
        let deezer = track(provider: .deezer, id: "preview", name: "Halo", artist: "Beyoncé")
        let spotify = track(provider: .spotify, id: "full", name: "Halo", artist: "Beyoncé")
        let grouped = MasterTrack.group([deezer, spotify])

        XCTAssertEqual(grouped[0].bestPlaybackSource()?.providerID, .spotify)
    }

    func testProviderPriorityBreaksEqualTierTie() {
        let apple = track(provider: .apple, id: "apple", name: "Halo", artist: "Beyoncé")
        let spotify = track(provider: .spotify, id: "spotify", name: "Halo", artist: "Beyoncé")
        let grouped = MasterTrack.group([apple, spotify])

        XCTAssertEqual(
            grouped[0].bestPlaybackSource(order: [.spotify, .apple])?.providerID,
            .spotify
        )
    }

    private func track(
        provider: ProviderID,
        id: String,
        name: String,
        artist: String
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
            durationMs: 180_000
        )
    }
}
