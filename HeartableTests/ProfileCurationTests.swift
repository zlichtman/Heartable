import XCTest
@testable import Heartable

final class ProfileCurationTests: XCTestCase {
    func testPlaylistRoundTripPreservesPublicProfileMetadata() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let playlist = UnifiedPlaylist(
            key: "spotify:playlist:road-trip",
            providerID: .spotify,
            playlistID: "road-trip",
            name: "Road Trip",
            description: "Windows down",
            image: URL(string: "https://example.com/road-trip.jpg"),
            trackCount: 42,
            owner: "Zach",
            createdAt: createdAt,
            contentRevision: "snapshot-road-trip"
        )
        let document = ProfileCurationDTO(
            playlists: [ProfilePlaylistDTO(playlist)],
            updatedAt: createdAt
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ProfileCurationDTO.self, from: data)
        let restored = try XCTUnwrap(decoded.playlists.first?.unified)

        XCTAssertEqual(decoded.version, ProfileCurationDTO.currentVersion)
        XCTAssertEqual(restored, playlist)
    }

    func testVersionOneCurationMigratesToDefaultProfileModules() throws {
        let data = Data(#"{"version":1,"playlists":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(ProfileCurationDTO.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.modules, ProfileModulePreferenceDTO.defaults)
    }

    func testProfileModuleNormalizationPreservesOrderAndFillsMissingModules() {
        let input = [
            ProfileModulePreferenceDTO(module: .listeningStats, isVisible: false),
            ProfileModulePreferenceDTO(module: .featuredPlaylists, isVisible: true),
            ProfileModulePreferenceDTO(module: .listeningStats, isVisible: true),
        ]

        let normalized = ProfileCurationDTO.normalizedModules(input)

        XCTAssertEqual(
            normalized.map(\.module),
            [.listeningStats, .featuredPlaylists, .compatibility, .topTracks,
             .sharedMixtapes, .musicLinks]
        )
        XCTAssertFalse(normalized[0].isVisible)
    }

    func testThemePresetKeysAreUnique() {
        let keys = Themes.all.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testThemeGalleryIsCompleteUniqueAndBrandLed() {
        XCTAssertEqual(Themes.gallery.first?.key, Themes.defaultKey)
        XCTAssertEqual(Set(Themes.galleryKeys).count, Themes.galleryKeys.count)
        XCTAssertEqual(Themes.gallery.count, Themes.galleryKeys.count)
        XCTAssertEqual(Themes.gallery.map(\.key), Themes.galleryKeys)
        XCTAssertTrue(Themes.gallery.allSatisfy { $0.palette.visualizer.count == 3 })
    }

    @MainActor
    func testThemeGalleryPrimaryTextMeetsWCAGAA() {
        for definition in Themes.gallery {
            let text = RGBAColor(definition.palette.text)
            let background = RGBAColor(definition.palette.bg)
            let card = RGBAColor(definition.palette.card)

            XCTAssertGreaterThanOrEqual(
                text.contrast(against: background),
                4.5,
                "\(definition.label) text must remain readable on its background"
            )
            XCTAssertGreaterThanOrEqual(
                text.contrast(against: card),
                4.5,
                "\(definition.label) text must remain readable on cards"
            )
        }
    }

    func testClassicTerminalPresetIsRegistered() {
        let terminal = Themes.byKey("classic-terminal")
        XCTAssertEqual(terminal.key, "classic-terminal")
        XCTAssertEqual(terminal.label, "Classic Terminal")
        XCTAssertEqual(terminal.group, .dark)
    }

    func testFeaturedPlaylistNormalizationPreservesOrderDeduplicatesAndCapsAtSix() {
        let input = [
            playlist("first"),
            playlist("second"),
            playlist("first"),
            playlist("third"),
            playlist("fourth"),
            playlist("fifth"),
            playlist("sixth"),
            playlist("seventh"),
        ]

        let normalized = MeStore.normalizedFeaturedPlaylists(input)

        XCTAssertEqual(
            normalized.map(\.key),
            ["spotify:first", "spotify:second", "spotify:third",
             "spotify:fourth", "spotify:fifth", "spotify:sixth"]
        )
    }

    @MainActor
    func testApplyingFeaturedPlaylistsUpdatesSharedStateImmediately() {
        let store = MeStore()
        let userID = UUID()
        let selection = [playlist("second"), playlist("first")]

        store.setFeaturedPlaylists(selection, userID: userID)

        XCTAssertTrue(store.hasLoadedFeaturedPlaylists)
        XCTAssertEqual(store.featuredPlaylists.map(\.key), ["spotify:second", "spotify:first"])
    }

    @MainActor
    func testApplyingProfileCurationUpdatesModuleOrderImmediately() {
        let store = MeStore()
        let userID = UUID()
        let modules = [
            ProfileModulePreferenceDTO(module: .listeningStats, isVisible: true),
            ProfileModulePreferenceDTO(module: .topTracks, isVisible: false),
            ProfileModulePreferenceDTO(module: .featuredPlaylists, isVisible: true),
        ]

        store.setProfileCuration(
            playlists: [playlist("first")],
            modules: modules,
            userID: userID
        )

        XCTAssertEqual(
            store.profileModules,
            ProfileCurationDTO.normalizedModules(modules)
        )
        XCTAssertEqual(store.featuredPlaylists.map(\.key), ["spotify:first"])
    }

    private func playlist(_ id: String) -> UnifiedPlaylist {
        UnifiedPlaylist(
            key: "spotify:\(id)",
            providerID: .spotify,
            playlistID: id,
            name: id.capitalized,
            description: nil,
            image: nil,
            trackCount: 0,
            owner: nil
        )
    }
}
