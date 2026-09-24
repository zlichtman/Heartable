import XCTest
@testable import Heartable

final class RadioAndLyricsTests: XCTestCase {
    @MainActor func testStationSavesSurviveRelaunchAndStayAccountScoped() throws {
        let suite = "RadioTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID(), other = UUID()
        let saved = SavedRadioStations(defaults: defaults)
        saved.activate(ownerID: owner)
        saved.toggle("wsum-fm")
        saved.toggle("kexp")
        saved.toggle("https://untrusted.example/stream")
        XCTAssertEqual(saved.ids, ["wsum-fm", "kexp"])
        saved.activate(ownerID: other)
        XCTAssertTrue(saved.ids.isEmpty)
        let restored = SavedRadioStations(defaults: defaults)
        restored.activate(ownerID: owner)
        XCTAssertEqual(restored.ids, ["wsum-fm", "kexp"])
        restored.toggle("wsum-fm")
        restored.toggle("kexp")
        XCTAssertTrue(restored.ids.isEmpty)
    }

    func testLyricsPreviewShowsContextWithoutInventingTiming() {
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: nil, count: 0)), [])
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: nil, count: 8)), [0, 1])
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: 4, count: 8)), [4, 5])
        XCTAssertEqual(Array(LyricsModel.previewIndices(active: 7, count: 8)), [7])
    }

    func testPrivateMixtapeMediaReferencesCannotSelectOtherBucketsOrPaths() {
        let path = "\(UUID())/\(UUID())/\(UUID()).jpg"
        XCTAssertEqual(MixtapeMediaReference.path(from: "heartable-media://mixtape-gifts/\(path)"), path)
        XCTAssertNil(MixtapeMediaReference.path(from: "heartable-media://avatars/\(path)"))
        XCTAssertNil(MixtapeMediaReference.path(from: "heartable-media://mixtape-gifts/../../private"))
        XCTAssertNil(MixtapeMediaReference.path(from: "https://example.com/\(path)"))
    }

}
