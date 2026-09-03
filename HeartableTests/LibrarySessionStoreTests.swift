import XCTest
@testable import Heartable

final class LibrarySessionStoreTests: XCTestCase {
    @MainActor
    func testSessionKeepsStableStoresAcrossTabReconstruction() {
        let session = LibrarySessionStore()
        let firstLibrary = session.library
        let firstMaster = session.master

        XCTAssertTrue(firstLibrary === session.library)
        XCTAssertTrue(firstMaster === session.master)
    }

    @MainActor
    func testResetRetainsStoreIdentityAndClearsSessionState() {
        let session = LibrarySessionStore()
        let library = session.library
        let master = session.master

        session.reset()

        XCTAssertTrue(library === session.library)
        XCTAssertTrue(master === session.master)
        XCTAssertFalse(session.cachedDataReady)
        XCTAssertFalse(session.synchronizing)
        XCTAssertTrue(session.library.playlists.isEmpty)
        XCTAssertTrue(session.master.tracks.isEmpty)
    }
}
