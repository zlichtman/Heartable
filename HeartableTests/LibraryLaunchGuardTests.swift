import XCTest
@testable import Heartable

@MainActor
final class LibraryLaunchGuardTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "LibraryLaunchGuardTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A TestFlight update must keep the cache-first library: re-deriving it
    /// means a full provider pull, which is what trips Spotify's rate limiter.
    func testBuildChangeKeepsCachesAndRecordsTheNewBuild() {
        var cleared = 0
        let first = LibraryLaunchGuard.prepareForLaunch(defaults: defaults, currentBuild: "66") { cleared += 1 }
        XCTAssertEqual(first, .keptAcrossBuildChange(previous: nil))
        LibraryLaunchGuard.finishBootstrap(defaults: defaults)

        let same = LibraryLaunchGuard.prepareForLaunch(defaults: defaults, currentBuild: "66") { cleared += 1 }
        XCTAssertEqual(same, .kept)

        let upgraded = LibraryLaunchGuard.prepareForLaunch(defaults: defaults, currentBuild: "69") { cleared += 1 }
        XCTAssertEqual(upgraded, .keptAcrossBuildChange(previous: "66"))
        XCTAssertEqual(cleared, 0)
        XCTAssertEqual(defaults.string(forKey: LibraryLaunchGuard.buildStampKey), "69")
    }

    func testCrashDuringBootstrapClearsCachesOnTheNextLaunch() {
        var cleared = 0
        _ = LibraryLaunchGuard.prepareForLaunch(defaults: defaults, currentBuild: "69") { cleared += 1 }
        LibraryLaunchGuard.beginBootstrap(defaults: defaults)
        // No finishBootstrap: the process died while decoding or syncing.
        let relaunch = LibraryLaunchGuard.prepareForLaunch(defaults: defaults, currentBuild: "69") { cleared += 1 }
        XCTAssertEqual(relaunch, .clearedAfterAbnormalEnd)
        XCTAssertEqual(cleared, 1)
        XCTAssertFalse(defaults.bool(forKey: LibraryLaunchGuard.bootstrapMarkerKey))
    }

    func testCleanBackgroundOrFinishedSyncIsNotTreatedAsACrash() {
        var cleared = 0
        _ = LibraryLaunchGuard.prepareForLaunch(defaults: defaults, currentBuild: "69") { cleared += 1 }
        LibraryLaunchGuard.beginBootstrap(defaults: defaults)
        LibraryLaunchGuard.finishBootstrap(defaults: defaults)
        XCTAssertEqual(LibraryLaunchGuard.prepareForLaunch(defaults: defaults, currentBuild: "69") { cleared += 1 }, .kept)
        XCTAssertEqual(cleared, 0)
    }

    func testRemoveLibraryCachesForEveryOwnerLeavesUnrelatedFiles() throws {
        let fm = FileManager.default
        let caches = try XCTUnwrap(fm.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let support = try XCTUnwrap(fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
            .appendingPathComponent("Heartable", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let owner = UUID().uuidString.lowercased()
        let library = caches.appendingPathComponent("heartable-library-cache-\(owner).json")
        let master = support.appendingPathComponent("master-library-\(owner).json")
        let unrelated = support.appendingPathComponent("weekly-recap-\(owner).json")
        for url in [library, master, unrelated] { try Data("{}".utf8).write(to: url) }
        defer { try? fm.removeItem(at: unrelated) }

        AccountSessionStore.removeLibraryCaches(ownerID: nil)

        XCTAssertFalse(fm.fileExists(atPath: library.path))
        XCTAssertFalse(fm.fileExists(atPath: master.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path), "Only derived library caches are removed")
    }
}
