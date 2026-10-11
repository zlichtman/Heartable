import SwiftUI

/// The app shell on the native iOS 26 system chrome: a real Liquid Glass tab bar
/// with the MiniPlayer riding in the tab view's bottom accessory (the Apple
/// Music arrangement). The system owns bar placement, content insets, scroll
/// frosting, and the minimize-on-scroll behavior, so music content never
/// collides with the nav or the player bar.
struct AppTabView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(ProvidersStore.self) private var providers
    @Environment(PlaybackPrefsStore.self) private var prefs
    @Environment(NowPlayingSync.self) private var nowPlayingSync
    @Environment(BannerCenter.self) private var banners
    @Environment(WeeklyRecapStore.self) private var weeklyRecap
    @Environment(LibrarySessionStore.self) private var librarySession
    @Environment(PlaylistTracksRepository.self) private var playlistTracks
    @Environment(BackupScheduler.self) private var backupScheduler
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @AppStorage("heartable.navigation.showNames")
    private var showNavigationNames = false

    @State private var selected: AppTab = .library
    @State private var showFullPlayer = false
    @State private var playerGeometry = PlaylistPlayerGeometry()

    // One navigation path per tab that pushes detail screens, so re-tapping the
    // active tab pops it back to its main page.
    @State private var libraryPath = NavigationPath()
    @State private var discoverPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var mixtapesPath: [UUID] = []

    /// The system tab bar re-sets the selection when the active tab is tapped
    /// again; this binding turns that into pop-to-root.
    private var selection: Binding<AppTab> {
        Binding(
            get: { selected },
            set: { tab in
                if tab == selected { popToRoot(tab) }
                else { MainThreadStallMonitor.note("tab \(tab)") }
                selected = tab
            }
        )
    }

    var body: some View {
        playerAttachedTabs
        .environment(\.playlistPlayerGeometry, playerGeometry)
        // Native accessory reparenting can disappear briefly during rotation.
        // Only disabling the shelf invalidates its last useful measurement.
        .onChange(of: reservesPlayer) {
            if !reservesPlayer { playerGeometry.clear() }
        }
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerView()
                .heartableSheetChrome(dragIndicator: .hidden)
        }
        // RootView's ordered bootstrap hydrates the cached library; this shell
        // only refreshes it once provider restoration reached a coherent state.
        .task(id: providers.refreshGeneration) {
            guard providers.hasRefreshed else { return }
            await librarySession.synchronize(
                providers: providers.libraryProviders,
                playlistTracks: playlistTracks
            )
            await backupScheduler.runIfDue(after: librarySession, using: playlistTracks)
        }
        .task {
            await weeklyRecap.load()
        }
        // Player/network polling exists only while the scene is usable. The task
        // is cancelled automatically on a phase transition, while `stop()` also
        // cancels PlayerStore's own adaptive polling loop.
        .task(id: scenePhase) {
            MainThreadStallMonitor.note("scene \(scenePhase)")
            let isActive = scenePhase == .active
            SpotifyAppRemote.shared.setActive(isActive)
            librarySession.setActive(isActive)
            if isActive {
                // iOS may suspend the exact-expiry task in the background.
                // Reconcile before playback polling can qualify another listen.
                prefs.refreshGhostMode()
                player.start()
                // A service that could not answer last time (rate limit, outage)
                // gets one quiet retry on return; a still-active cooldown makes
                // this a no-op that keeps the notice current.
                if (librarySession.needsSynchronization || librarySession.library.providerNotice != nil), providers.hasRefreshed {
                    await librarySession.synchronize(
                        providers: providers.libraryProviders,
                        playlistTracks: playlistTracks
                    )
                }
                await backupScheduler.runIfDue(after: librarySession, using: playlistTracks)
            } else {
                player.stop()
            }
        }
        // Listen qualification and skip regions follow every player refresh,
        // including position ticks. Only this invisible leaf observes them; the
        // shell above it (TabView, native accessory, tab-bar policy) observes
        // `nowSummary`.
        .background { NowPlayingSyncDriver() }
        .onChange(of: prefs.mode) {
            Task { await player.applyPlaybackMode(prefs.mode) }
        }
        .onChange(of: player.feedbackID) {
            guard let message = player.feedbackMessage else { return }
            banners.show(
                message,
                style: message.hasPrefix("Playing from")
                    ? .info
                    : .error
            )
        }
    }

    /// Own the player presentation at the stable app-shell level. The mini-player
    /// can change between playing and idle without destroying an open sheet.
    @ViewBuilder
    private var playerAttachedTabs: some View {
        if #available(iOS 26.1, *) {
            tabs
                // Reserve this before rotation, even when idle. Starting playback
                // changes the row's contents, never the shelf's available height.
                .tabViewBottomAccessory(isEnabled: reservesPlayer) {
                    playerAccessory
                }
        } else {
            // iOS 26.0 has no isEnabled overload. Keep one stable TabView
            // instead of destroying its navigation subtree when playback starts.
            tabs.tabViewBottomAccessory {
                playerAccessory
            }
        }
    }

    private var reservesPlayer: Bool {
        PlaylistChromePolicy.reservesPlayer(playlistVisible: PlaylistRotation.hasVisiblePlaylist,
                                           hasNowPlaying: player.nowSummary != nil)
    }

    private var playerAccessory: some View {
        MiniPlayer { showFullPlayer = true }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                playerGeometry.update($0, scale: displayScale)
            }
    }

    private var tabs: some View {
        TabView(selection: selection) {
            Tab(value: .discover) {
                DiscoverView(navPath: $discoverPath)
            } label: {
                tabLabel(.discover)
            }
            Tab(value: .mixtapes) {
                MixtapesView(path: $mixtapesPath, onFindFriends: showFriendSearch)
            } label: {
                tabLabel(.mixtapes)
            }
            Tab(value: .library) {
                LibraryView(navPath: $libraryPath)
            } label: {
                tabLabel(.library)
            }
            Tab(value: .backups) {
                BackupsView()
            } label: {
                tabLabel(.backups)
            }
            Tab(value: .profile) {
                ProfileView(navPath: $profilePath)
            } label: {
                tabLabel(.profile)
            }
        }
        .tint(theme.palette.rose)
        // The iOS 27 Liquid Glass bar can briefly re-resolve its material/tint
        // when tab-item labels animate between title+icon and icon-only layouts.
        // Update the native item metadata in place without animating that
        // preference transition; selection and minimize animations are untouched.
        .animation(nil, value: showNavigationNames)
        // Collapsing an idle five-icon bar into one icon feels like lost
        // navigation. Only allow the compact system state while the mini-player
        // is present and actually benefits from the reclaimed space.
        .tabBarMinimizeBehavior(PlaylistChromePolicy.allowsMinimizing(
            playlistVisible: PlaylistRotation.hasVisiblePlaylist,
            hasNowPlaying: player.nowSummary != nil,
            systemSupportsStableAccessory: PlaylistChromePolicy.systemSupportsStableAccessory
        ) ? .onScrollDown : .never)
    }

    @ViewBuilder
    private func tabLabel(_ tab: AppTab) -> some View {
        // Keep one stable native label structure while changing only its title.
        // An empty title yields the requested icon-only item without rebuilding
        // the hosted tab label or losing the tab's spoken accessibility name.
        Label(showNavigationNames ? tab.title : "", systemImage: tab.icon)
            .accessibilityLabel(tab.title)
    }

    /// Opens the Heartable tab on friend search, e.g. from the mixtape
    /// recipient picker when there's no one to send to yet.
    private func showFriendSearch() {
        var route = NavigationPath()
        route.append(FindFriendsRoute())
        discoverPath = route
        selected = .discover
    }

    /// Tapping the already-selected tab pops it back to its main page.
    private func popToRoot(_ tab: AppTab) {
        switch tab {
        // Replacing an already-empty path rebuilds the tab's NavigationStack,
        // which restarts Library hydration/index work and makes a harmless re-tap
        // look frozen on large libraries. Only mutate a path when there is
        // something to pop.
        case .library where !libraryPath.isEmpty:
            libraryPath = NavigationPath()
        case .discover where !discoverPath.isEmpty:
            discoverPath = NavigationPath()
        case .profile where !profilePath.isEmpty:
            profilePath = NavigationPath()
        case .mixtapes where !mixtapesPath.isEmpty:
            mixtapesPath = []
        case .backups: break // no nested navigation
        case .library, .discover, .profile, .mixtapes: break
        }
    }
}

/// Forwards every player refresh to listen qualification. It is the only view
/// in the shell that observes `PlayerStore.now` itself, so a progress poll
/// re-evaluates this empty view rather than the whole TabView.
private struct NowPlayingSyncDriver: View {
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs
    @Environment(NowPlayingSync.self) private var nowPlayingSync
    @Environment(PlaybackEngine.self) private var engine
    @Environment(SkipStore.self) private var skips
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            // PlayerStore refreshes actively playing sources every few seconds.
            // Drive listen qualification and skip regions from those position
            // updates rather than a separate timer.
            .onChange(of: player.now, initial: true) {
                sync()
                applySkips()
            }
            .onChange(of: prefs.ghostMode) { sync() }
    }

    private func sync() {
        let now = player.now
        let ghost = prefs.ghostMode
        Task { await nowPlayingSync.sync(now: now, ghost: ghost) }
    }

    private func applySkips() {
        guard scenePhase == .active else { return }
        let now = player.now
        Task { await engine.apply(now: now, skips: skips, player: player) }
    }
}
