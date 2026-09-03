import SwiftUI

/// App gate: restored auth → onboarding → tab shell.
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
    @Environment(BackupScheduler.self) private var backupScheduler
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
        return onboardedIDs.contains(id) || me.hasCompletedOnboarding
    }

    private func markOnboarded() {
        guard let userID = auth.userID else { return }
        let id = userID.uuidString
        var ids = onboardedIDs
        ids.insert(id)
        onboardedIDsRaw = ids.sorted().joined(separator: ",")
        me.markOnboardingCompleted(userID: userID)
        Task { try? await BackendAPI.shared.completeOnboarding(userID: userID) }
    }

    var body: some View {
        Group {
            if !auth.isConfigured {
                configNeeded
            } else if !auth.loaded {
                launchPlaceholder
            } else if auth.session == nil {
                AuthView()
            } else if !me.hasResolvedAccount && !isOnboarded {
                // A reinstall has no local onboarding marker. Resolve the account
                // profile before deciding whether setup is needed, avoiding a
                // one-frame flash of onboarding for an established account.
                launchPlaceholder
            } else if !isOnboarded {
                OnboardingView { markOnboarded() }
            } else {
                // Key the whole authed shell on the user id so every per-view @State
                // (LibraryStore, Backups list, Mixtapes, Friends) is rebuilt fresh
                // when the account changes — no stale data carries across accounts.
                AppTabView().id(auth.userID)
            }
        }
        .preferredColorScheme(
            !auth.loaded
                ? .dark
                : (theme.current.group == .dark ? .dark : .light)
        )
        // Hydrate the account-scoped cached identity before the Profile tab is
        // ever opened, then reconcile it with Supabase in the background.
        .task(id: auth.userID) {
            // This task is the single owner of account activation. Keeping reset
            // and bootstrap in one ordered path avoids the former `.onChange`
            // race where a provider restore could start and then be cleared by a
            // second lifecycle callback during the first authenticated frame.
            resetAccountState()
            guard let userID = auth.userID else { return }
            me.activate(userID: userID)
            async let profile: Void = me.load(userID: userID)
            async let connections: Void = providers.activate(userID: userID)
            await profile
            await connections

            // Migrate the former per-install completion marker to the account.
            if onboardedIDs.contains(userID.uuidString),
               !me.hasCompletedOnboarding {
                do {
                    try await BackendAPI.shared.completeOnboarding(userID: userID)
                    me.markOnboardingCompleted(userID: userID)
                } catch { /* Retried on the next account activation. */ }
            }

            // Automatic backups must not start from the app-level launch task:
            // at that point Supabase may not have restored the session namespace
            // yet. Run only after account and provider bootstrap is complete.
            await backupScheduler.runIfDue(userID: userID)
        }
    }

    /// Clear only in-memory account state. Durable account profile/provider data
    /// stays scoped in cache, Keychain, and Supabase for the subsequent restore.
    private func resetAccountState() {
        me.reset()
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

    /// Match the system launch screen while the persisted auth session resolves.
    /// There is deliberately no logo, animation, spinner, or artificial minimum
    /// duration: a returning user should reach cached app content immediately.
    private var launchPlaceholder: some View {
        Color("LaunchBackground").ignoresSafeArea()
            .accessibilityHidden(true)
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
