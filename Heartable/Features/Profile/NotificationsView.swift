import SwiftUI
import UserNotifications
import UIKit

/// Notification preferences, wired the standard way: the master row requests the
/// real iOS notification permission, reflects the system authorization status, and
/// deep-links to Settings when notifications are turned off there. The per-category
/// toggles persist to `@AppStorage` and gate which notifications fire once the push
/// pipeline (APNs + Supabase triggers) is connected.
struct NotificationsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("heartable.notifications.allow") private var allow = true
    @AppStorage("heartable.notifications.friendRequests") private var friendRequests = true
    @AppStorage("heartable.notifications.friendNowPlaying") private var friendNowPlaying = false
    @AppStorage("heartable.notifications.mixtapeShares") private var mixtapeShares = true
    @AppStorage("heartable.notifications.weeklyLeaderboard") private var weeklyLeaderboard = true
    @AppStorage("heartable.notifications.backupComplete") private var backupComplete = true

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var requesting = false

    /// Categories are live only when the OS has granted permission and the user
    /// hasn't muted everything locally.
    private var enabled: Bool { status == .authorized && allow }

    var body: some View {
        SettingsScaffold(title: "Notifications") {
            card { permissionRow }

            sectionHeader("Social")
            card {
                VStack(spacing: 0) {
                    toggleRow(icon: "person.badge.plus", label: "Friend requests",
                              isOn: $friendRequests, disabled: !enabled)
                    divider
                    toggleRow(icon: "waveform", label: "Friend now-playing",
                              subtitle: "Quiet by default", isOn: $friendNowPlaying, disabled: !enabled)
                    divider
                    toggleRow(icon: "heart.fill", label: "Mixtape shares",
                              isOn: $mixtapeShares, disabled: !enabled)
                }
            }

            sectionHeader("Gamification")
            card {
                toggleRow(icon: "trophy.fill", label: "Weekly leaderboard digest",
                          isOn: $weeklyLeaderboard, disabled: !enabled)
            }

            sectionHeader("System")
            card {
                toggleRow(icon: "checkmark.icloud.fill", label: "Backup complete",
                          isOn: $backupComplete, disabled: !enabled)
            }

            Text(footerText)
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
                .padding(.top, 4)
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
        // Keep the weekly leaderboard digest (a local notification) in sync with
        // the toggles and the system authorization status the moment they change.
        .onChange(of: weeklyLeaderboard) { _, _ in LocalNotifier.syncScheduledFromPrefs() }
        .onChange(of: allow) { _, _ in LocalNotifier.syncScheduledFromPrefs() }
        .onChange(of: status) { _, _ in LocalNotifier.syncScheduledFromPrefs() }
    }

    // MARK: - Permission row (status-aware)

    @ViewBuilder
    private var permissionRow: some View {
        switch status {
        case .authorized, .provisional, .ephemeral:
            toggleRow(icon: "bell.fill", label: "Allow notifications", isOn: $allow)
        case .denied:
            Button { openSystemSettings() } label: {
                actionRow(icon: "bell.slash.fill",
                          label: "Notifications are off",
                          subtitle: "Turn them on in iOS Settings",
                          trailing: "Open Settings")
            }
            .buttonStyle(.plain)
        default: // .notDetermined
            Button { Task { await request() } } label: {
                actionRow(icon: "bell.fill",
                          label: "Turn on notifications",
                          subtitle: "Get friend requests, shares, and digests",
                          trailing: requesting ? nil : "Enable",
                          showSpinner: requesting)
            }
            .buttonStyle(.plain)
            .disabled(requesting)
        }
    }

    private var footerText: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "The weekly leaderboard digest and backup-complete alerts are delivered now. Friend requests, friend now-playing, and mixtape shares are coming with push support."
        case .denied:
            return "Notifications are turned off for Heartable in iOS Settings."
        default:
            return "Enable notifications to choose what Heartable can notify you about."
        }
    }

    // MARK: - Permission actions

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    private func request() async {
        requesting = true
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { allow = true }
        await refreshStatus()
        requesting = false
        if granted {
            banners.success("Notifications enabled")
        } else {
            banners.info("Notifications remain off")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        banners.info("Opening iOS notification settings")
        UIApplication.shared.open(url)
    }

    // MARK: - Atoms

    private func actionRow(icon: String, label: String, subtitle: String,
                           trailing: String?, showSpinner: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.palette.rose)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Typography.semibold(14)).foregroundStyle(theme.palette.text)
                Text(subtitle).font(Typography.body(12)).foregroundStyle(theme.palette.textMuted)
            }
            Spacer(minLength: 4)
            if showSpinner {
                ProgressView().controlSize(.small)
            } else if let trailing {
                Text(trailing).font(Typography.semibold(13)).foregroundStyle(theme.palette.rose)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func toggleRow(
        icon: String,
        label: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>,
        disabled: Bool = false
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                }
            }
        }
        .tint(theme.palette.rose)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Divider().overlay(theme.palette.border)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
            .padding(.top, 6)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(theme.palette.border, lineWidth: 1)
            )
    }
}
