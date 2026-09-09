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
/// - the optional weekly reminder — a repeating calendar notification kept in
///   sync with the user's preferences.
///
/// Everything reads authorization status and the `@AppStorage`-backed prefs from
/// `UserDefaults` before doing anything, and no-ops gracefully when notifications
/// are not allowed. Safe to call from a `@MainActor` context.
@MainActor
enum LocalNotifier {
    // Notification header icons belong to iOS, not this content payload.
    // ThemeStore updates UIApplication's alternate icon. Do not attach a fake
    // sender avatar or delete/repost delivered notifications to force an icon
    // refresh: neither is a supported app-icon cache invalidation mechanism.

    /// Stable identifier for the single repeating weekly digest request.
    private static let weeklyDigestID = HeartableNotificationCategory.weeklyReminder.rawValue
    private static var scheduleRevision: UInt = 0
    private static var scheduleTask: Task<Void, Never>?

    // MARK: - Immediate one-shot

    /// Fire an immediate local notification. No-ops gracefully if the user has
    /// not authorized notifications. Safe to call from `@MainActor`.
    static func send(
        title: String,
        body: String,
        categoryIdentifier: String = "heartable.general"
    ) {
        Task {
            let category = HeartableNotificationCategory.resolve(categoryIdentifier)
            guard HeartableNotificationPreferences.read().allows(category) else { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            case .notDetermined:
                // Heartable routes short-lived feedback through Apple's native
                // notification UI. Provisional authorization makes that path
                // available without surprising someone with a permission prompt
                // during an unrelated action; the Notifications screen remains
                // the contextual place to opt into normal alerts.
                let granted = (try? await center.requestAuthorization(
                    options: [.alert, .sound, .provisional]
                )) ?? false
                guard granted else { return }
            case .denied:
                return
            @unknown default:
                return
            }
            // Permission UI can suspend this task while preferences change.
            let preferences = HeartableNotificationPreferences.read()
            guard preferences.allows(category) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = preferences.playsSound(for: category) ? .default : nil
            content.categoryIdentifier = categoryIdentifier
            content.threadIdentifier = category.threadIdentifier
            content.interruptionLevel = .active
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                // A nil trigger asks iOS to deliver the notification immediately.
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    // MARK: - Weekly leaderboard digest

    /// Keep the existing entry point for launch callers. This is an opt-in
    /// Sunday 6pm reminder, not a claim that new listening data is available.
    static func scheduleWeeklyLeaderboardDigest() {
        syncScheduledFromPrefs()
    }

    /// Remove the pending weekly digest by its stable identifier.
    static func cancelWeeklyLeaderboardDigest() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [weeklyDigestID])
    }

    /// Reconcile the scheduled weekly digest against the current prefs + auth
    /// status. Safe to call at launch and whenever a relevant toggle changes.
    static func syncScheduledFromPrefs() {
        scheduleRevision &+= 1
        guard scheduleTask == nil else { return }
        scheduleTask = Task {
            defer { scheduleTask = nil }
            var appliedRevision: UInt
            repeat {
                appliedRevision = scheduleRevision
                await reconcileWeeklyReminder()
            } while appliedRevision != scheduleRevision
        }
    }

    private static func reconcileWeeklyReminder() async {
        let authorized = await isAuthorized()
        let preferences = HeartableNotificationPreferences.read()
        guard authorized, preferences.allows(.weeklyReminder) else {
            cancelWeeklyLeaderboardDigest()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your week in music"
        content.body = "Open Heartable for your weekly recap and friends’ leaderboard."
        content.sound = preferences.playsSound(for: .weeklyReminder) ? .default : nil
        content.categoryIdentifier = HeartableNotificationCategory.weeklyReminder.rawValue
        content.threadIdentifier = HeartableNotificationCategory.weeklyReminder.threadIdentifier

        var components = DateComponents()
        components.weekday = 1 // Sunday (1 = Sunday in Gregorian calendar)
        components.hour = 18
        components.minute = 0
        let request = UNNotificationRequest(
            identifier: weeklyDigestID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        let center = UNUserNotificationCenter.current()
        // Adding the same identifier replaces it atomically; removing first
        // creates an avoidable gap and races another preference update.
        try? await center.add(request)
        // A preference change can race the asynchronous add. Never leave a
        // reminder queued after its own switch or the master was turned off.
        if !HeartableNotificationPreferences.read().allows(.weeklyReminder) {
            cancelWeeklyLeaderboardDigest()
        }
    }

    /// Re-check preferences at presentation time as well as enqueue time. This
    /// covers already-queued local requests when settings change in the app.
    nonisolated static func foregroundOptions(
        categoryIdentifier: String,
        preferences: HeartableNotificationPreferences = .read()
    ) -> UNNotificationPresentationOptions {
        let category = HeartableNotificationCategory.resolve(categoryIdentifier)
        guard preferences.allows(category) else { return [] }
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if preferences.playsSound(for: category) { options.insert(.sound) }
        return options
    }

    // MARK: - Helpers

    private static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}
