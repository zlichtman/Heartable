import XCTest
import SwiftUI
import Observation
@testable import Heartable

@MainActor
final class LibraryRenderingTests: XCTestCase {
    func testAutomaticBackupCannotStartBeforeLibraryIsReady() async {
        await AccountSessionStore.prepare(for: UUID())
        let scheduler = BackupScheduler()
        withObservationTracking { _ = scheduler.isRunning } onChange: {
            XCTFail("An incomplete library must not start provider probes or backup work")
        }
        await scheduler.runIfDue(after: LibrarySessionStore(),
                                 using: PlaylistTracksRepository(persistenceEnabled: false))
        XCTAssertFalse(scheduler.isRunning)
        await AccountSessionStore.prepare(for: nil)
    }

    func testCustomSortingDoesNotWriteWhileRendering() {
        let sort = LibrarySortStore()
        let previous = sort.sortMode
        defer { sort.sortMode = previous }
        sort.activate(ownerID: UUID())
        sort.sortMode = .custom
        sort.setCustomOrder(["old", "b", "a", "b"])
        let catalog = [playlist("a"), playlist("b"), playlist("new")]
        let saved = sort.customOrder
        for _ in 0..<100 {
            XCTAssertEqual(sort.sorted(catalog).map(\.key), ["new", "b", "a"])
        }
        XCTAssertEqual(sort.customOrder, saved, "Drawing must not change observable or persisted order")
        sort.syncCustomOrder(with: catalog)
        XCTAssertEqual(sort.customOrder, ["new", "b", "a"])
        XCTAssertEqual(sort.sorted(catalog).map(\.key), ["new", "b", "a"])
    }

    func testAccessoryIgnoresSubpixelNoiseAndInvalidTransientMeasurements() {
        let geometry = PlaylistPlayerGeometry()
        let frame = CGRect(x: 20, y: 700, width: 350, height: 44)
        geometry.update(frame, scale: 3)
        withObservationTracking { _ = geometry.frame } onChange: {
            XCTFail("Equivalent measurements must not schedule more layout")
        }
        for offset in [0.01, -0.01, 0.1, -0.1] {
            geometry.update(frame.offsetBy(dx: offset, dy: offset), scale: 3)
        }
        geometry.update(.zero, scale: 3)
        geometry.update(CGRect(x: 0, y: CGFloat.nan, width: 100, height: 44), scale: 3)
        XCTAssertEqual(geometry.frame, frame)
    }

    func testMeasuringAccessoryDoesNotRedrawTheTabOwner() async throws {
        let probe = RenderProbe()
        let geometry = PlaylistPlayerGeometry()
        let (window, previous) = try makeWindow()
        let host = UIHostingController(rootView: GeometryOwner(probe: probe, geometry: geometry))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(200))
        let renders = probe.renders
        for index in 0..<30 {
            geometry.update(CGRect(x: 20, y: 700 - index, width: 350, height: 44), scale: 3)
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(probe.renders, renders, "The shell must not read the measurement it produces")
        XCTAssertEqual(probe.lastFrame?.minY, 671)
    }

    func testLargePlaylistMountsBoundedRowsAndSurvivesResizing() async throws {
        let songs = (0..<3_000).map { index in
            UnifiedTrack(key: "spotify:\(index)", providerID: .spotify, providerTrackID: "\(index)",
                         uri: "spotify:track:\(index)", name: "Song \(index)",
                         artists: [.init(id: "a", name: "Artist")], album: "Album",
                         albumArt: nil, durationMs: 180_000)
        }
        let catalog = playlist("large", count: songs.count)
        let repo = PlaylistTracksRepository(fetch: { _ in .success(songs) }, persistenceEnabled: false)
        await repo.load(catalog)
        let (window, previous) = try makeWindow()
        let theme = ThemeStore()
        let host = UIHostingController(rootView:
            NavigationStack {
                PlaylistDetailView(playlist: catalog)
            }
            .environment(theme).environment(repo).environment(PlayerStore())
            .environment(PlaybackPrefsStore()).environment(LibrarySortStore())
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(500))
        let list = try XCTUnwrap(collectionView(in: host.view))
        let count = (0..<list.numberOfSections).reduce(0) { $0 + list.numberOfItems(inSection: $1) }
        XCTAssertGreaterThan(count, 100)
        XCTAssertLessThan(count, 110, "Opening a playlist must not eagerly expand all 3,000 songs")
        for size in [CGSize(width: 844, height: 390), CGSize(width: 390, height: 844)] {
            window.frame.size = size
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(repo.tracks(for: catalog).count, 3_000, "Bounded rendering must preserve the full queue")
    }

    private func playlist(_ key: String, count: Int = 0) -> UnifiedPlaylist {
        .init(key: key, providerID: .spotify, playlistID: key, name: key,
              description: nil, image: nil, trackCount: count, owner: nil)
    }

    private func makeWindow() throws -> (UIWindow, UIWindow?) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return (window, previous)
    }

    private func collectionView(in view: UIView) -> UICollectionView? {
        if let list = view as? UICollectionView { return list }
        return view.subviews.lazy.compactMap { self.collectionView(in: $0) }.first
    }
}

@MainActor private final class RenderProbe {
    var renders = 0
    var lastFrame: CGRect?
}

private struct GeometryOwner: View {
    let probe: RenderProbe
    let geometry: PlaylistPlayerGeometry
    var body: some View {
        probe.renders += 1
        return TabView {
            Tab("Library", systemImage: "house") { GeometryConsumer(probe: probe) }
        }
        .environment(\.playlistPlayerGeometry, geometry)
    }
}

private struct GeometryConsumer: View {
    @Environment(\.playlistPlayerGeometry) private var geometry
    let probe: RenderProbe
    var body: some View {
        let frame = geometry?.frame
        Color.clear.onChange(of: frame, initial: true) { probe.lastFrame = frame }
    }
}
