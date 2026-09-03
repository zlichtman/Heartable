import Foundation
import UserNotifications

/// Local-notification delivery. These fire entirely on-device through
/// `UNUserNotificationCenter`, so they work today without the APNs + Supabase
/// push pipeline that the social events (friend requests, now-playing, shares)
/// still depend on.
///
/// Two kinds live here:
/// - `send(title:body:)` — an immediate one-shot, used by features as things
///   happen (e.g. the backups feature fires "Backup complete").
/// - the weekly leaderboard digest — a repeating calendar notification kept in
///   sync with the user's preferences.
///
/// Everything reads authorization status and the `@AppStorage`-backed prefs from
/// `UserDefaults` before doing anything, and no-ops gracefully when notifications
/// are not allowed. Safe to call from a `@MainActor` context.
enum LocalNotifier {

    // MARK: - Preference keys (mirror the @AppStorage keys in NotificationsView)

    private enum Key {
        static let allow = "heartable.notifications.allow"
        static let weeklyLeaderboard = "heartable.notifications.weeklyLeaderboard"
    }

    /// Stable identifier for the single repeating weekly digest request.
    private static let weeklyDigestID = "heartable.notifications.weeklyLeaderboard.digest"

    // MARK: - Immediate one-shot

    /// Fire an immediate local notification. No-ops gracefully if the user has
    /// not authorized notifications. Safe to call from `@MainActor`.
    static func send(
        title: String,
        body: String,
        categoryIdentifier: String = "heartable.general"
    ) {
        Task {
            guard await isAuthorized(), prefAllow() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.interruptionLevel = .active
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                // A nil trigger asks iOS to deliver the notification immediately.
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Weekly leaderboard digest

    /// Schedule the repeating weekly leaderboard digest (Sunday 6pm) with a stable
    /// identifier, but only when permission is authorized and both the master
    /// `allow` and the `weeklyLeaderboard` prefs are on. Replaces any existing one.
    static func scheduleWeeklyLeaderboardDigest() {
        Task {
            guard await isAuthorized(), prefAllow(), prefWeekly() else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your weekly leaderboard"
            content.body = "See how you and your friends ranked this week on Heartable."
            content.sound = .default

            var components = DateComponents()
            components.weekday = 1 // Sunday (1 = Sunday in Gregorian calendar)
            components.hour = 18
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let request = UNNotificationRequest(
                identifier: weeklyDigestID,
                content: content,
                trigger: trigger
            )
            let center = UNUserNotificationCenter.current()
            // Clear the prior pending request so re-scheduling never stacks duplicates.
            center.removePendingNotificationRequests(withIdentifiers: [weeklyDigestID])
            try? await center.add(request)
        }
    }

    /// Remove the pending weekly digest by its stable identifier.
    static func cancelWeeklyLeaderboardDigest() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [weeklyDigestID])
    }

    /// Reconcile the scheduled weekly digest against the current prefs + auth
    /// status. Safe to call at launch and whenever a relevant toggle changes.
    static func syncScheduledFromPrefs() {
        Task {
            if await isAuthorized(), prefAllow(), prefWeekly() {
                scheduleWeeklyLeaderboardDigest()
            } else {
                cancelWeeklyLeaderboardDigest()
            }
        }
    }

    // MARK: - Helpers

    private static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// `@AppStorage` defaults registered values to their declared default only at
    /// the property wrapper; raw `UserDefaults` returns `false`/`nil` until first
    /// write. These prefs default to `true` in the UI, so treat "unset" as `true`.
    private static func prefAllow() -> Bool {
        UserDefaults.standard.object(forKey: Key.allow) as? Bool ?? true
    }

    private static func prefWeekly() -> Bool {
        UserDefaults.standard.object(forKey: Key.weeklyLeaderboard) as? Bool ?? true
    }
}
