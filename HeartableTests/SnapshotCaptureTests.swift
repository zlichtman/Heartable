import XCTest
@testable import Heartable

final class SnapshotCaptureTests: XCTestCase {
    func testChildInsertsAreBatchedAndTagged() {
        XCTAssertEqual(BackendAPI.batches(Array(0..<1_201), size: 500).map(\.count), [500, 500, 201])
        XCTAssertEqual(BackendAPI.batches([Int](), size: 500).count, 0)
        XCTAssertEqual(BackendAPI.providerRawValue(forURI: "apple:track:123"), "apple")
        XCTAssertEqual(BackendAPI.providerRawValue(forURI: "spotify:track:abc"), "spotify")
        XCTAssertEqual(BackendAPI.providerRawValue(forURI: "https://legacy/uri"), "spotify")
    }

    func testOnlyTypedProvidersAbortABackupOnAnUnavailableRead() {
        XCTAssertTrue(BackendAPI.strictReadProviders.contains(.spotify))
        XCTAssertTrue(BackendAPI.strictReadProviders.contains(.apple))
        XCTAssertFalse(BackendAPI.strictReadProviders.contains(.plex),
                       "Legacy adapters answer unavailable for an empty collection too")
    }
}
