import SwiftUI
import UIKit

/// Owns the per-window orientation policy (playlist landscape rotation).
final class HeartableAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        #if DEBUG
        // The gallery fixture starts directly on a playlist, before the normal
        // app shell activates its visibility-driven rotation policy.
        if ScreenshotFixtures.requested == "vinyl" { return .landscape }
        #endif
        return PlaylistRotation.supportedOrientations
    }
}

@main
struct HeartableApp: App {
    @UIApplicationDelegateAdaptor(HeartableAppDelegate.self)
    private var appDelegate

    @State private var theme = ThemeStore()
    @State private var auth = AuthStore()
    @State private var providers = ProvidersStore()
    @State private var player = PlayerStore()
    @State private var prefs = PlaybackPrefsStore()
    @State private var nowPlayingSync = NowPlayingSync()
    @State private var relationships = FriendRelationships()
    @State private var skips = SkipStore()
    @State private var engine = PlaybackEngine()
    @State private var me = MeStore()
    @State private var librarySort = LibrarySortStore()
    @State private var banners = BannerCenter.shared
    @State private var backupScheduler = BackupScheduler()
    @State private var topTracks = TopTracksRepository()
    @State private var playlistTracks = PlaylistTracksRepository()
    @State private var librarySession = LibrarySessionStore()
    @State private var friendActivity = FriendActivityRepository()
    @State private var weeklyRecap = WeeklyRecapStore()

    init() {
        RuntimeConfiguration.configure()
        // Before any store can decode a library cache: a previous run that died
        // inside that decode must not have its caches replayed into the same crash.
        LibraryLaunchGuard.prepareForLaunch()

        // SwiftUI navigation titles render in the system font; make them use the
        // brand serif (Playfair Display) app-wide so they match in-content headings.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        if let large = UIFont(name: "PlayfairDisplay-Bold", size: 32) {
            appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: UIColor.label]
        }
        if let inline = UIFont(name: "PlayfairDisplay-Bold", size: 18) {
            appearance.titleTextAttributes = [.font: inline, .foregroundColor: UIColor.label]
        }
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    /// Debug screenshot fixtures replace the app gate; Release always shows RootView.
    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if ScreenshotFixtures.requested == "mixtape" {
            ScreenshotMixtapeView()
        } else if ScreenshotFixtures.requested == "vinyl" {
            ScreenshotVinylView()
        } else if ScreenshotFixtures.requested == "friend" {
            ScreenshotFriendView()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(theme)
                .environment(auth)
                .environment(providers)
                .environment(player)
                .environment(prefs)
                .environment(nowPlayingSync)
                .environment(relationships)
                .environment(skips)
                .environment(engine)
                .environment(me)
                .environment(librarySort)
                .environment(banners)
                .environment(backupScheduler)
                .environment(topTracks)
                .environment(playlistTracks)
                .environment(librarySession)
                .environment(friendActivity)
                .environment(weeklyRecap)
                .onOpenURL {
                    if SpotifyNativeSignIn.shared.handle($0) { return }
                    SpotifyAppRemote.shared.handle($0)
                }
                // Feedback toasts live in their own pass-through window so they
                // draw above sheets and full-screen covers.
                .background(ToastWindowInstaller(banners: banners, theme: theme))
                .task {
                    // Reconcile the opt-in weekly reminder. Initial backup
                    // scheduling is account-bootstrap work owned by RootView.
                    WeeklyReminder.sync()
                }
        }
    }
}
