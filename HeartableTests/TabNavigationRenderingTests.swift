import XCTest
import SwiftUI
import Observation
@testable import Heartable

/// Exercise the native tab/accessory container as well as the destination itself.
/// A standalone NavigationStack misses accessory reparenting during tab changes.
@MainActor
@available(iOS 26.1, *)
final class TabNavigationRenderingTests: XCTestCase {
    func testBackupsInAppShellWithoutPlayer() async throws {
        try await exerciseBackups(reservePlayer: false)
    }

    func testBackupsInAppShellWithReservedPlayer() async throws {
        try await exerciseBackups(reservePlayer: true)
    }

    func testBackupsInAppShellWithPausedTrack() async throws {
        try await exerciseBackups(reservePlayer: false, pausedTrack: true)
    }

    private func exerciseBackups(reservePlayer: Bool, pausedTrack: Bool = false) async throws {
        await AccountSessionStore.prepare(for: nil)
        let visibilityID = UUID()
        if reservePlayer { PlaylistRotation.setVisible(true, id: visibilityID) }
        defer { PlaylistRotation.setVisible(false, id: visibilityID) }
        let links = WidgetLinks()
        let player = PlayerStore()
        if pausedTrack {
            guard !SpotifyAuth.isSignedIn else { throw XCTSkip("Requires the isolated, signed-out simulator") }
            // Missing credentials stops transport before any API call, while
            // preserving the selected song as the real paused/retry player state.
            await player.play(UnifiedTrack(key: "spotify:fixture", providerID: .spotify,
                providerTrackID: "fixture", uri: "spotify:track:fixture", name: "Fixture song",
                artists: [.init(id: "a", name: "Artist")], album: "Album", albumArt: nil, durationMs: 180_000))
            XCTAssertNotNil(player.now)
        }
        let host = UIHostingController(rootView: AppTabView()
            .environment(ThemeStore()).environment(player)
            .environment(ProvidersStore()).environment(PlaybackPrefsStore())
            .environment(NowPlayingSync()).environment(SkipStore())
            .environment(PlaybackEngine()).environment(FriendLinks())
            .environment(links).environment(BannerCenter())
            .environment(WeeklyRecapStore()).environment(LibrarySessionStore())
            .environment(PlaylistTracksRepository(persistenceEnabled: false))
            .environment(BackupScheduler()).environment(LibrarySortStore())
            .environment(MeStore()).environment(AuthStore())
            .environment(TopTracksRepository()).environment(ChatStore())
            .environment(FriendActivityRepository()).environment(\.scenePhase, .inactive))
        let (window, previous) = try show(host)
        defer { window.isHidden = true; previous?.makeKey(); player.stop() }
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<3 {
            for route in [HeartableWidgetRoute.backups, .library] {
                let started = ContinuousClock.now
                links.handle(route.url)
                try await Task.sleep(for: .milliseconds(300))
                host.view.layoutIfNeeded()
                let tabs = try XCTUnwrap(tabController(in: host))
                XCTAssertEqual(tabs.selectedIndex, route == .backups ? 3 : 2)
                XCTAssertLessThan(started.duration(to: .now), .seconds(2),
                                  "Changing tabs must leave the main actor responsive")
            }
        }
    }

    func testLargePlaylistNavigatesInsideNativeTabsAndPlayer() async throws {
        let tracks = (0..<10_000).map { index in
            UnifiedTrack(key: "spotify:\(index)", providerID: .spotify,
                         providerTrackID: "\(index)", uri: "spotify:track:\(index)",
                         name: "Song \(index)", artists: [.init(id: "a", name: "Artist")],
                         album: "Album", albumArt: nil, durationMs: 180_000)
        }
        let playlist = UnifiedPlaylist(key: "large", providerID: .spotify, playlistID: "large",
                                       name: "Large playlist", description: nil, image: nil,
                                       trackCount: tracks.count, owner: nil)
        let repository = PlaylistTracksRepository(fetch: { _ in .success(tracks) }, persistenceEnabled: false)
        await repository.load(playlist)
        let navigation = NavigationFixtureState()
        let host = UIHostingController(rootView: NativePlaylistFixture(state: navigation)
            .environment(ThemeStore()).environment(PlayerStore())
            .environment(repository).environment(PlaybackPrefsStore())
            .environment(LibrarySortStore()))
        let (window, previous) = try show(host)
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<3 {
            let started = ContinuousClock.now
            navigation.path.append(playlist)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertTrue(PlaylistRotation.hasVisiblePlaylist)
            XCTAssertLessThan(started.duration(to: .now), .seconds(2))
            navigation.selected = 1
            try await Task.sleep(for: .milliseconds(300))
            navigation.selected = 0
            try await Task.sleep(for: .milliseconds(300))
            navigation.path = NavigationPath()
            try await Task.sleep(for: .milliseconds(400))
        }
        XCTAssertEqual(repository.tracks(for: playlist).count, tracks.count)
    }

    private func show<Content: View>(_ host: UIHostingController<Content>) throws -> (UIWindow, UIWindow?) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        return (window, previous)
    }

    private func tabController(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        return controller.children.lazy.compactMap { self.tabController(in: $0) }.first
    }
}

@MainActor @Observable private final class NavigationFixtureState {
    var path = NavigationPath()
    var selected = 0
}

@available(iOS 26.1, *)
private struct NativePlaylistFixture: View {
    @Bindable var state: NavigationFixtureState
    @State private var geometry = PlaylistPlayerGeometry()
    @Environment(\.displayScale) private var scale

    var body: some View {
        TabView(selection: $state.selected) {
            Tab("Library", systemImage: "house", value: 0) {
                NavigationStack(path: $state.path) {
                    Text("Library").navigationDestination(for: UnifiedPlaylist.self) {
                        PlaylistDetailView(playlist: $0)
                    }
                }
            }
            Tab("Backups", systemImage: "externaldrive", value: 1) { Text("Backups") }
        }
        .tabViewBottomAccessory(isEnabled: PlaylistRotation.hasVisiblePlaylist) {
            MiniPlayer(onOpen: {})
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    geometry.update($0, scale: scale)
                }
        }
        .tabBarMinimizeBehavior(.never)
        .environment(\.playlistPlayerGeometry, geometry)
    }
}
