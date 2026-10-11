import SwiftUI
import UserNotifications
import UIKit

/// Notification settings. Heartable's only system notification is the opt-in
/// Sunday weekly reminder; everyday feedback (saves, errors, backups) appears as
/// in-app toasts. Turning the reminder on is the one place Heartable asks for
/// iOS notification permission, and the screen links to Settings if it was
/// declined there.
struct NotificationsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(WeeklyReminder.preferenceKey) private var weeklyReminder = false

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var requesting = false

    private var denied: Bool { status == .denied }

    var body: some View {
        SettingsScaffold(title: "Notifications") {
            card {
                VStack(spacing: 0) {
                    toggleRow(icon: "calendar", label: "Weekly reminder",
                              subtitle: "Sundays at 6 PM: your recap and friends’ leaderboard",
                              isOn: reminderBinding, disabled: requesting || denied)
                    if denied {
                        divider
                        Button { openSystemSettings() } label: {
                            actionRow(icon: "bell.slash.fill",
                                      label: "Notifications are off",
                                      subtitle: "Allow them in iOS Settings to get the reminder",
                                      trailing: "Open Settings")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Confirmations and errors appear briefly at the top of the screen while you use Heartable.")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
                .padding(.top, 4)
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
        // Keep the scheduled reminder in sync with the switch and the system
        // authorization status the moment either changes.
        .onChange(of: weeklyReminder) { _, _ in WeeklyReminder.sync() }
        .onChange(of: status) { _, _ in WeeklyReminder.sync() }
    }

    /// Shows off while iOS blocks notifications, and asks for permission the
    /// first time the reminder is turned on.
    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { weeklyReminder && !denied },
            set: { isOn in
                guard isOn else {
                    weeklyReminder = false
                    return
                }
                Task { await enableReminder() }
            }
        )
    }

    // MARK: - Permission

    private func enableReminder() async {
        requesting = true
        defer { requesting = false }
        if status == .notDetermined {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            await refreshStatus()
        }
        switch status {
        case .authorized, .provisional, .ephemeral: weeklyReminder = true
        default: weeklyReminder = false
        }
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Atoms

    private func actionRow(icon: String, label: String, subtitle: String,
                           trailing: String) -> some View {
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
            Text(trailing).font(Typography.semibold(13)).foregroundStyle(theme.palette.rose)
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
