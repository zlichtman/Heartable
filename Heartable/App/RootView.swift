import SwiftUI

/// App gate: splash → auth → onboarding → tab shell.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ThemeStore.self) private var theme
    // Shared stores that hold per-account in-memory state; reset on sign-out/delete
    // so a different (or re-created) account never inherits the previous user's data.
    @Environment(MeStore.self) private var me
    @Environment(ProvidersStore.self) private var providers
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingSync.self) private var nowPlayingSync
    @Environment(PlaybackPrefsStore.self) private var prefs
    @Environment(SkipStore.self) private var skips
    @Environment(TopTracksRepository.self) private var topTracks
    @Environment(PlaylistTracksRepository.self) private var playlistTracks
    @Environment(LibrarySessionStore.self) private var librarySession
    @Environment(ChatStore.self) private var chats
    @Environment(FriendActivityRepository.self) private var friendActivity
    @Environment(WeeklyRecapStore.self) private var weeklyRecap
    @State private var minimumLaunchElapsed = false

    // Onboarding is tracked per account, not per device: store the user IDs that
    // have finished it. Keying on the user (instead of a single device-wide flag)
    // stops a second account inheriting the first's "already onboarded" state, and
    // stops a returning user being re-onboarded just because the flag was a single
    // shared bool. The wipe on account deletion still clears this with the domain.
    @AppStorage("heartable.onboarded.userIDs") private var onboardedIDsRaw = ""

    private var onboardedIDs: Set<String> {
        Set(onboardedIDsRaw.split(separator: ",").map(String.init))
    }

    private var isOnboarded: Bool {
        guard let id = auth.userID?.uuidString else { return false }
        return onboardedIDs.contains(id)
    }

    private func markOnboarded() {
        guard let id = auth.userID?.uuidString else { return }
        var ids = onboardedIDs
        ids.insert(id)
        onboardedIDsRaw = ids.sorted().joined(separator: ",")
    }

    var body: some View {
        Group {
            if !auth.isConfigured {
                configNeeded
            } else if !auth.loaded || !minimumLaunchElapsed {
                splash
                    .transition(.opacity)
            } else if auth.session == nil {
                AuthView()
            } else if !isOnboarded {
                OnboardingView { markOnboarded() }
            } else {
                // Key the whole authed shell on the user id so every per-view @State
                // (LibraryStore, Backups list, Mixtapes, Friends) is rebuilt fresh
                // when the account changes — no stale data carries across accounts.
                AppTabView().id(auth.userID)
            }
        }
        // Keep the handoff from the native launch screen to SwiftUI calm and
        // continuous instead of flashing directly into the authenticated shell.
        .animation(.easeOut(duration: 0.18), value: auth.loaded && minimumLaunchElapsed)
        .preferredColorScheme(
            !auth.loaded || !minimumLaunchElapsed
                ? .dark
                : (theme.current.group == .dark ? .dark : .light)
        )
        .task {
            // Very fast auth restores used to skip SwiftUI's first branded frame,
            // leaving only whichever launch snapshot iOS happened to cache. Keep a
            // short, consistent handoff without delaying genuinely slow startup.
            guard !minimumLaunchElapsed else { return }
            try? await Task.sleep(for: .milliseconds(650))
            minimumLaunchElapsed = true
        }
        // Hydrate the account-scoped cached identity before the Profile tab is
        // ever opened, then reconcile it with Supabase in the background.
        .task(id: auth.userID) {
            guard let userID = auth.userID else { return }
            me.activate(userID: userID)
            await me.load(userID: userID)
        }
        // On any account transition, clear the shared in-memory stores so the
        // previous account's profile, services, now-playing, and weights cannot
        // linger into the newly mounted shell.
        .onChange(of: auth.userID, initial: true) { oldID, newID in
            if oldID != newID {
                me.activate(userID: newID)
                providers.reset()
                player.reset()
                nowPlayingSync.reset()
                prefs.reset()
                skips.reset()
                topTracks.reset()
                playlistTracks.reset()
                librarySession.reset()
                chats.reset()
                friendActivity.reset()
                weeklyRecap.reset()
                WidgetSnapshotStore.clearAndReloadWidgets()
            }
        }
    }

    private var splash: some View {
        ZStack {
            // The native launch screen supplies this same canvas. It deliberately
            // has no image because iOS cannot make launch-screen artwork follow
            // the user's selected alternate app icon.
            Color("LaunchBackground").ignoresSafeArea()
            HeartableLaunchAnimation()
        }
    }

    private var configNeeded: some View {
        ZStack {
            theme.palette.bg.ignoresSafeArea()
            Text("Set SUPABASE_HOST + SUPABASE_ANON_KEY in Secrets.xcconfig to run Heartable.")
                .font(Typography.body(15))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(32)
        }
    }
}
