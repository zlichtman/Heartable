import SwiftUI
import UIKit

@main
struct HeartableApp: App {
    @State private var theme = ThemeStore()
    @State private var auth = AuthStore()
    @State private var providers = ProvidersStore()
    @State private var player = PlayerStore()
    @State private var prefs = PlaybackPrefsStore()
    @State private var nowPlayingSync = NowPlayingSync()
    @State private var friendLinks = FriendLinks()
    @State private var skips = SkipStore()
    @State private var engine = PlaybackEngine()
    @State private var me = MeStore()
    @State private var librarySort = LibrarySortStore()
    @State private var banners = BannerCenter()
    @State private var backupScheduler = BackupScheduler()
    @State private var topTracks = TopTracksRepository()
    @State private var playlistTracks = PlaylistTracksRepository()
    @State private var chats = ChatStore()
    @State private var friendActivity = FriendActivityRepository()
    @State private var weeklyRecap = WeeklyRecapStore()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        RuntimeConfiguration.configure()

        // SwiftUI navigation titles render in the system font; make them use the
        // brand serif (Playfair Display) app-wide so the headings match the RN app.
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

    var body: some Scene {
        WindowGroup {
            RootView()
                // bannerHost reads ThemeStore from the environment, so it must be
                // applied BEFORE the .environment injections (which wrap it as the
                // parent) — otherwise it can't find ThemeStore and crashes on launch.
                .bannerHost(banners)
                .environment(theme)
                .environment(auth)
                .environment(providers)
                .environment(player)
                .environment(prefs)
                .environment(nowPlayingSync)
                .environment(friendLinks)
                .environment(skips)
                .environment(engine)
                .environment(me)
                .environment(librarySort)
                .environment(banners)
                .environment(backupScheduler)
                .environment(topTracks)
                .environment(playlistTracks)
                .environment(chats)
                .environment(friendActivity)
                .environment(weeklyRecap)
                .onOpenURL { friendLinks.handle($0) }
                .task {
                    // Reconcile the weekly local-notification digest with the saved
                    // prefs, and run a scheduled backup if one is due on this launch.
                    LocalNotifier.syncScheduledFromPrefs()
                    await backupScheduler.runIfDue()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await backupScheduler.runIfDue() }
                    }
                }
        }
    }
}
