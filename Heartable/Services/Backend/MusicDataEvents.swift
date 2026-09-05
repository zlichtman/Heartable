import Foundation

extension Notification.Name {
    /// Internal UI invalidation, not a user-facing toast/notification.
    static let heartableMusicDataCleared = Notification.Name("heartable.musicDataCleared")
    static let heartableBackupCreated = Notification.Name("heartable.backupCreated")
}
