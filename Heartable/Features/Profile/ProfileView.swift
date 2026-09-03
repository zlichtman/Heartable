import SwiftUI

/// Profile tab — an iOS-Settings-style hub. The identity button at the top (photo,
/// name, handle, now-playing) opens your friends-facing profile, which is where you
/// view and edit it. Everything below is the rest of the settings, grouped by area.
struct ProfileView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(AuthStore.self) private var auth
    @Environment(MeStore.self) private var me
    @Environment(PlayerStore.self) private var player
    @Environment(WeeklyRecapStore.self) private var weeklyRecap
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var navPath: NavigationPath

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                pageHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        identityBanner
                        weeklyRecapCard
                            .padding(.horizontal, 16)
                        settingsSection
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 32)
                }
            }
            .background(theme.palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UnifiedPlaylist.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: HeartableWidgetRoute.self) { _ in WeeklyRecapView() }
        }
        .task(id: auth.userID) { await me.load(userID: auth.userID) }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HeartablePageHeader(tab: .profile)
    }

    // MARK: - Weekly recap

    private var weeklyRecapCard: some View {
        NavigationLink { WeeklyRecapView() } label: {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.palette.roseDim)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "heart.text.clipboard.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(theme.palette.rose)
                            .accessibilityHidden(true)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly recap")
                        .font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.text)
                    Text(weeklyRecapSubtitle)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if weeklyRecap.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.palette.rose)
                        .accessibilityLabel("Refreshing weekly recap")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.palette.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background {
                ZStack {
                    theme.palette.card
                    LinearGradient(
                        colors: [
                            theme.palette.rose.opacity(0.10),
                            theme.palette.grad1.opacity(0.06),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(theme.palette.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this week and your recap archive")
    }

    private var weeklyRecapSubtitle: String {
        guard let recap = weeklyRecap.current, !recap.isEmpty else {
            return "Your week takes shape as you listen"
        }
        return "\(recap.playCount) plays · "
            + WeeklyRecap.compactDuration(recap.estimatedListeningMilliseconds)
            + " estimated"
    }

    // MARK: - Account banner (opens the friends-facing profile)

    private var identityBanner: some View {
        NavigationLink { MyProfileView() } label: {
            VStack(alignment: .leading, spacing: 18) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        AvatarCircle(urlString: me.avatarUrlString, name: displayName, size: 76)
                            .overlay {
                                Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                            }
                        identityText
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        AvatarCircle(urlString: me.avatarUrlString, name: displayName, size: 76)
                            .overlay {
                                Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                            }

                        identityText
                        Spacer(minLength: 0)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        nowPlayingLine
                        Spacer(minLength: 8)
                        viewProfileAffordance
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        nowPlayingLine
                        viewProfileAffordance
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    theme.palette.bgElevated
                    LinearGradient(
                        colors: [
                            theme.palette.rose.opacity(0.20),
                            theme.palette.violet.opacity(0.08),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(theme.palette.rose.opacity(0.75))
                    .frame(height: 2)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.palette.border)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName), \(handleLine). View profile")
        .accessibilityHint("Opens the profile your friends see")
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("YOUR ACCOUNT")
                .font(Typography.semibold(11))
                .tracking(1.2)
                .foregroundStyle(theme.palette.textSecondary)

            Text(displayName)
                .font(Typography.heading(24))
                .foregroundStyle(theme.palette.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(handleLine)
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var viewProfileAffordance: some View {
        HStack(spacing: 7) {
            Text("View profile")
                .font(Typography.semibold(13))
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(theme.palette.rose, in: Capsule())
    }

    private var nowPlayingLine: some View {
        HStack(spacing: 7) {
            Image(systemName: player.now?.isPlaying == true ? "waveform" : "moon.zzz.fill")
                .font(.system(size: 11, weight: .semibold))

            Group {
                if let now = player.now {
                    Text("\(now.name) · \(now.artist)")
                        .foregroundStyle(theme.palette.rose)
                } else {
                    Text("Not listening")
                        .foregroundStyle(theme.palette.textMuted)
                }
            }
        }
        .font(Typography.medium(12))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(player.now == nil ? theme.palette.textMuted : theme.palette.rose)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETTINGS")
                .font(Typography.semibold(12))
                .tracking(1)
                .foregroundStyle(theme.palette.textMuted)

            SettingsGroup {
                settingsRow("music.note.list", "Music Services",
                            "Connections and playback availability") { MusicServicesView() }
                settingsRow("clock.arrow.circlepath", "Listening History",
                            "Your plays, plus Ghost Mode") { ListeningHistoryView() }
                settingsRow("paintpalette.fill", "Appearance",
                            "App theme and icon") { AppearanceView() }
                settingsRow("slider.horizontal.3", "Sounds",
                            "Crossfade and in-app playback volume") { SoundsView() }
                settingsRow("bell.fill", "Notifications",
                            "Weekly digest and alert preferences") { NotificationsView() }
                settingsRow("person.crop.circle", "Account",
                            "Sign out, delete account", last: true) { AccountView() }
            }
        }
    }

    @ViewBuilder
    private func settingsRow<D: View>(_ icon: String, _ label: String, _ subtitle: String,
                                      last: Bool = false,
                                      @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(theme.palette.rose)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .accessibilityHidden(true)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.palette.textMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: 54)
                if !last {
                    Divider().overlay(theme.palette.border).padding(.leading, 54)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(subtitle)")
    }

    private var displayName: String { me.displayName }
    private var handleLine: String {
        if let h = me.handle, !h.isEmpty { return "@\(h)" }
        return "Tap to set up your profile"
    }
}
