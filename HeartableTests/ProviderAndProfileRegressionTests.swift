import XCTest
@testable import Heartable

final class ProviderAndProfileRegressionTests: XCTestCase {
    func testSpotifyLongRangeUsesAllCompactLabel() {
        XCTAssertEqual(StatRange.shortTerm.compactLabel, "4 wk")
        XCTAssertEqual(StatRange.mediumTerm.compactLabel, "6 mo")
        XCTAssertEqual(StatRange.longTerm.compactLabel, "All")
    }

    func testSupabaseWrappedMissingProfileCurationIsEmptyState() throws {
        let wrapped = try XCTUnwrap(
            #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#
                .data(using: .utf8)
        )
        XCTAssertTrue(
            BackendAPI.isMissingStorageObject(statusCode: 400, data: wrapped)
        )
        XCTAssertTrue(
            BackendAPI.isMissingStorageObject(statusCode: 404, data: Data())
        )
    }

    func testOtherStorageFailuresRemainFailures() throws {
        let forbidden = try XCTUnwrap(
            #"{"statusCode":"403","error":"forbidden","message":"Denied"}"#
                .data(using: .utf8)
        )
        XCTAssertFalse(
            BackendAPI.isMissingStorageObject(statusCode: 400, data: forbidden)
        )
        XCTAssertFalse(
            BackendAPI.isMissingStorageObject(statusCode: 500, data: Data())
        )
    }

    func testAppleCatalogSearchEncodesReservedCharactersAsOneTerm() throws {
        let query = "AC/DC & Earth+Wind? x=y 日本"
        let url = try XCTUnwrap(
            AppleMusicAPI.catalogSearchURL(
                storefront: "us",
                query: query,
                limit: 99
            )
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value)
            }
        )
        XCTAssertEqual(items["term"]!, query)
        XCTAssertEqual(items["types"]!, "songs")
        XCTAssertEqual(items["limit"]!, "25")
    }

    func testTrackRefreshPreservesLastKnownArtwork() throws {
        let art = try XCTUnwrap(URL(string: "https://example.com/cover.jpg"))
        let cached = track(art: art)
        let partial = track(art: nil)
        XCTAssertEqual(partial.preservingArtwork(from: cached).albumArt, art)
    }

    func testFreshTrackArtworkWinsOverCachedArtwork() throws {
        let old = try XCTUnwrap(URL(string: "https://example.com/old.jpg"))
        let new = try XCTUnwrap(URL(string: "https://example.com/new.jpg"))
        XCTAssertEqual(
            track(art: new).preservingArtwork(from: track(art: old)).albumArt,
            new
        )
    }

    func testPlaylistRefreshPreservesLastKnownArtwork() throws {
        let art = try XCTUnwrap(URL(string: "https://example.com/playlist.jpg"))
        let cached = playlist(art: art)
        let partial = playlist(art: nil)
        XCTAssertEqual(partial.preservingArtwork(from: cached).image, art)
    }

    func testMergedTrackArtworkDoesNotDependOnProviderResponseOrder() throws {
        let spotifyArt = try XCTUnwrap(URL(string: "https://example.com/spotify.jpg"))
        let appleArt = try XCTUnwrap(URL(string: "https://example.com/apple.jpg"))
        let spotify = track(provider: .spotify, id: "s1", art: spotifyArt)
        let apple = track(provider: .apple, id: "a1", art: appleArt)

        let forward = try XCTUnwrap(MasterTrack.group([apple, spotify]).first)
        let reversed = try XCTUnwrap(MasterTrack.group([spotify, apple]).first)

        XCTAssertEqual(forward.albumArt, spotifyArt)
        XCTAssertEqual(reversed.albumArt, spotifyArt)
    }

    func testArtistFallbackArtworkIsStableAcrossTrackOrder() throws {
        let spotifyArt = try XCTUnwrap(URL(string: "https://example.com/artist-spotify.jpg"))
        let appleArt = try XCTUnwrap(URL(string: "https://example.com/artist-apple.jpg"))
        let spotify = track(
            provider: .spotify,
            id: "s1",
            name: "Later Song",
            art: spotifyArt
        )
        let apple = track(
            provider: .apple,
            id: "a1",
            name: "Earlier Song",
            art: appleArt
        )

        let forward = try XCTUnwrap(
            MasterArtist.aggregate(MasterTrack.group([apple, spotify])).first
        )
        let reversed = try XCTUnwrap(
            MasterArtist.aggregate(MasterTrack.group([spotify, apple])).first
        )

        XCTAssertEqual(forward.artURL, spotifyArt)
        XCTAssertEqual(reversed.artURL, spotifyArt)
    }

    private func track(art: URL?) -> UnifiedTrack {
        track(provider: .apple, id: "1", art: art)
    }

    private func track(
        provider: ProviderID,
        id: String,
        name: String = "Song",
        art: URL?
    ) -> UnifiedTrack {
        UnifiedTrack(
            key: "\(provider.rawValue):\(id)",
            providerID: provider,
            providerTrackID: id,
            uri: "\(provider.rawValue):song:\(id)",
            name: name,
            artists: [UnifiedArtist(id: "Artist", name: "Artist")],
            album: "Album",
            albumArt: art,
            durationMs: 180_000
        )
    }

    private func playlist(art: URL?) -> UnifiedPlaylist {
        UnifiedPlaylist(
            key: "apple:p1",
            providerID: .apple,
            playlistID: "p1",
            name: "Playlist",
            description: nil,
            image: art,
            trackCount: 4,
            owner: "Listener"
        )
    }
}
