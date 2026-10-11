import Foundation
import UserNotifications

/// The opt-in Sunday weekly reminder: Heartable's only system notification.
/// In-app feedback is a toast (`BannerCenter`), never a notification.
///
/// The reminder is a repeating calendar notification kept in sync with the
/// user's switch and the iOS authorization status. Permission is requested only
/// when the user turns the reminder on (see `NotificationsView`).
@MainActor
enum WeeklyReminder {
    /// `@AppStorage` key for the switch. Off by default: a calendar reminder
    /// cannot establish that new recap data exists, so nobody gets an
    /// unconditional weekly announcement without asking for it.
    static let preferenceKey = "heartable.notifications.weeklyLeaderboard"

    /// Stable identifier for the single repeating request.
    private static let requestID = "heartable.notifications.weeklyLeaderboard.digest"
    private static var scheduleRevision: UInt = 0
    private static var scheduleTask: Task<Void, Never>?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? false
    }

    /// Reconcile the scheduled reminder (Sunday 6 PM) against the preference and
    /// authorization status. Safe to call at launch and whenever either changes.
    static func sync() {
        scheduleRevision &+= 1
        guard scheduleTask == nil else { return }
        scheduleTask = Task {
            defer { scheduleTask = nil }
            var appliedRevision: UInt
            repeat {
                appliedRevision = scheduleRevision
                await reconcile()
            } while appliedRevision != scheduleRevision
        }
    }

    private static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestID])
    }

    private static func reconcile() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let authorized: Bool = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
        guard authorized, isEnabled else {
            cancel()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your week in music"
        content.body = "Open Heartable for your weekly recap and friends’ leaderboard."
        content.sound = .default
        content.threadIdentifier = requestID

        var components = DateComponents()
        components.weekday = 1 // Sunday (1 = Sunday in Gregorian calendar)
        components.hour = 18
        components.minute = 0
        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        // Adding the same identifier replaces it atomically; removing first
        // creates an avoidable gap and races another preference update.
        try? await center.add(request)
        // A preference change can race the asynchronous add. Never leave a
        // reminder queued after its switch was turned off.
        if !isEnabled { cancel() }
    }
}
