import SwiftUI
import UserNotifications
import UIKit

/// Notification preferences, wired the standard way: the master row requests the
/// real iOS notification permission, reflects the system authorization status, and
/// deep-links to Settings when notifications are turned off there. The per-category
/// toggles persist to `@AppStorage` and gate the notification categories that are
/// implemented in the current build. Future remote-push categories stay hidden
/// until an APNs pipeline exists, so the settings never promise a dead control.
struct NotificationsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(HeartableNotificationPreferences.Key.allow) private var allow = true
    @AppStorage(HeartableNotificationPreferences.Key.actionUpdates) private var actionUpdates = true
    @AppStorage(HeartableNotificationPreferences.Key.weeklyReminder) private var weeklyReminder = false
    @AppStorage(HeartableNotificationPreferences.Key.backupComplete) private var backupComplete = true
    @AppStorage(HeartableNotificationPreferences.Key.sounds) private var sounds = true

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var alertSetting: UNNotificationSetting = .notSupported
    @State private var soundSetting: UNNotificationSetting = .notSupported
    @State private var requesting = false

    /// Categories are live only when the OS has granted permission and the user
    /// hasn't muted everything locally.
    private var enabled: Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: allow
        default: false
        }
    }

    var body: some View {
        SettingsScaffold(title: "Notifications") {
            card { permissionRow }

            sectionHeader("Updates")
            card {
                VStack(spacing: 0) {
                    toggleRow(icon: "checkmark.circle.fill", label: "Routine confirmations",
                              subtitle: "Saves, connections, and completed actions",
                              isOn: $actionUpdates, disabled: !enabled)
                    divider
                    toggleRow(icon: "checkmark.icloud.fill", label: "Automatic backups",
                              isOn: $backupComplete, disabled: !enabled)
                    divider
                    toggleRow(icon: "calendar", label: "Weekly reminder",
                              subtitle: "Sundays at 6 PM",
                              isOn: $weeklyReminder, disabled: !enabled)
                }
            }

            Text("Playback and failed-action alerts stay on while notifications are enabled.")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)

            sectionHeader("Delivery")
            card {
                VStack(spacing: 0) {
                    toggleRow(icon: "speaker.wave.2.fill", label: "Sounds",
                              subtitle: soundSetting == .disabled
                                  ? "Sounds are off in iOS Settings"
                                  : "Errors, backups, and reminders",
                              isOn: $sounds, disabled: !enabled)
                    divider
                    Button { openSystemSettings() } label: {
                        actionRow(icon: "gearshape.fill", label: "iOS Settings",
                                  subtitle: "Banners, Lock Screen, and Focus",
                                  trailing: "Open")
                    }
                    .buttonStyle(.plain)
                }
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
        .onChange(of: weeklyReminder) { _, _ in LocalNotifier.syncScheduledFromPrefs() }
        .onChange(of: sounds) { _, _ in LocalNotifier.syncScheduledFromPrefs() }
        .onChange(of: allow) { _, _ in LocalNotifier.syncScheduledFromPrefs() }
        .onChange(of: status) { _, _ in LocalNotifier.syncScheduledFromPrefs() }
    }

    // MARK: - Permission row (status-aware)

    @ViewBuilder
    private var permissionRow: some View {
        switch status {
        case .authorized, .ephemeral:
            toggleRow(icon: "bell.fill", label: "Allow notifications", isOn: $allow)
        case .provisional:
            VStack(spacing: 0) {
                toggleRow(icon: "bell.fill", label: "Allow notifications", isOn: $allow)
                divider
                Button { Task { await request() } } label: {
                    actionRow(
                        icon: "bell.badge.fill",
                        label: "Notifications are quiet",
                        subtitle: "Allow banners and sounds in iOS",
                        trailing: requesting ? nil : "Turn On",
                        showSpinner: requesting
                    )
                }
                .buttonStyle(.plain)
                .disabled(requesting)
            }
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
                          subtitle: "Action alerts, backups, and reminders",
                          trailing: requesting ? nil : "Enable",
                          showSpinner: requesting)
            }
            .buttonStyle(.plain)
            .disabled(requesting)
        }
    }

    private var footerText: String {
        switch status {
        case .authorized, .ephemeral:
            if !allow { return "Heartable notifications are paused on this device." }
            if alertSetting == .disabled {
                return "Banners are off in iOS Settings. Notifications may still appear in Notification Center."
            }
            return "Routine confirmations are always silent. iOS controls when notifications appear."
        case .provisional:
            return "Heartable notifications currently arrive quietly. Turn on banners and sounds above if you want immediate alerts."
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
        alertSetting = settings.alertSetting
        soundSetting = settings.soundSetting
    }

    private func request() async {
        requesting = true
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { allow = true }
        await refreshStatus()
        requesting = false
        // The permission row itself reflects the result. Do not send a
        // notification about notification settings (especially when denied).
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
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
