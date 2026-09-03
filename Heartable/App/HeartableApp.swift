import SwiftUI
import UIKit
import UserNotifications

/// Makes local notifications visible while Heartable is in the foreground.
/// Without this delegate, iOS stores the request but suppresses its banner while
/// the app is active—the exact time most action feedback occurs.
final class HeartableNotificationDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        PlaylistRotation.supportedOrientations
    }
}

@main
struct HeartableApp: App {
    @UIApplicationDelegateAdaptor(HeartableNotificationDelegate.self)
    private var notificationDelegate

    @State private var theme = ThemeStore()
    @State private var auth = AuthStore()
    @State private var providers = ProvidersStore()
    @State private var player = PlayerStore()
    @State private var prefs = PlaybackPrefsStore()
    @State private var nowPlayingSync = NowPlayingSync()
    @State private var friendLinks = FriendLinks()
    @State private var widgetLinks = WidgetLinks()
    @State private var skips = SkipStore()
    @State private var engine = PlaybackEngine()
    @State private var me = MeStore()
    @State private var librarySort = LibrarySortStore()
    @State private var banners = BannerCenter()
    @State private var backupScheduler = BackupScheduler()
    @State private var topTracks = TopTracksRepository()
    @State private var playlistTracks = PlaylistTracksRepository()
    @State private var librarySession = LibrarySessionStore()
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
                .environment(theme)
                .environment(auth)
                .environment(providers)
                .environment(player)
                .environment(prefs)
                .environment(nowPlayingSync)
                .environment(friendLinks)
                .environment(widgetLinks)
                .environment(skips)
                .environment(engine)
                .environment(me)
                .environment(librarySort)
                .environment(banners)
                .environment(backupScheduler)
                .environment(topTracks)
                .environment(playlistTracks)
                .environment(librarySession)
                .environment(chats)
                .environment(friendActivity)
                .environment(weeklyRecap)
                .onOpenURL {
                    friendLinks.handle($0)
                    widgetLinks.handle($0)
                }
                .task {
                    // Reconcile the weekly local-notification digest. Initial
                    // backup scheduling is account-bootstrap work owned by RootView.
                    LocalNotifier.syncScheduledFromPrefs()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active,
                       auth.loaded,
                       let userID = auth.userID,
                       AccountSessionStore.currentOwnerID == userID {
                        Task { await backupScheduler.runIfDue(userID: userID) }
                    }
                }
        }
    }
}
