import Foundation

/// Categories describe why a notification exists, not how a feature displays it.
/// Actionable failures deliberately do not share the routine-updates switch.
enum HeartableNotificationCategory: String, Sendable {
    case attentionNeeded = "heartable.feedback.error"
    case actionUpdates = "heartable.actionUpdates"
    case backupComplete = "heartable.backup.complete"
    case weeklyReminder = "heartable.notifications.weeklyLeaderboard.digest"

    static func resolve(_ identifier: String) -> Self {
        Self(rawValue: identifier) ?? .actionUpdates
    }

    var threadIdentifier: String { rawValue }
}

/// These are device notification preferences, matching iOS authorization rather
/// than a music-provider account. Existing explicit choices keep their keys.
struct HeartableNotificationPreferences: Equatable, Sendable {
    enum Key {
        static let allow = "heartable.notifications.allow"
        static let actionUpdates = "heartable.notifications.actionUpdates"
        static let backupComplete = "heartable.notifications.backupComplete"
        static let weeklyReminder = "heartable.notifications.weeklyLeaderboard"
        static let sounds = "heartable.notifications.sounds"
    }

    var allow = true
    var actionUpdates = true
    var backupComplete = true
    // A calendar reminder cannot establish that new recap data exists. Make it
    // opt-in instead of sending everyone an unconditional weekly announcement.
    var weeklyReminder = false
    var sounds = true

    static func read(from defaults: UserDefaults = .standard) -> Self {
        Self(
            allow: defaults.object(forKey: Key.allow) as? Bool ?? true,
            actionUpdates: defaults.object(forKey: Key.actionUpdates) as? Bool ?? true,
            backupComplete: defaults.object(forKey: Key.backupComplete) as? Bool ?? true,
            weeklyReminder: defaults.object(forKey: Key.weeklyReminder) as? Bool ?? false,
            sounds: defaults.object(forKey: Key.sounds) as? Bool ?? true
        )
    }

    func allows(_ category: HeartableNotificationCategory) -> Bool {
        guard allow else { return false }
        switch category {
        case .attentionNeeded: return true
        case .actionUpdates: return actionUpdates
        case .backupComplete: return backupComplete
        case .weeklyReminder: return weeklyReminder
        }
    }

    func playsSound(for category: HeartableNotificationCategory) -> Bool {
        // Saving, connecting, copying, and other routine confirmations should
        // not interrupt music. Important errors and opted-in events may sound.
        allows(category) && sounds && category != .actionUpdates
    }
}
