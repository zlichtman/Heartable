import Foundation

/// The single routing point for short-lived app feedback.
///
/// The historical name is retained so feature code does not need to know how
/// feedback is delivered. Unlike the old implementation, this type never draws
/// an in-app toast. Every message is handed to Apple's notification system by
/// `LocalNotifier`, which also makes foreground feedback use the same native
/// banner, accessibility, and user settings as background notifications.
@MainActor
@Observable
final class BannerCenter {
    struct Notification: Equatable, Sendable {
        let title: String
        let body: String
        let categoryIdentifier: String
    }

    enum Style: String, Equatable, Sendable {
        case success, error, info

        fileprivate var categoryIdentifier: String {
            "heartable.feedback.\(rawValue)"
        }
    }

    typealias Delivery = @MainActor (Notification) -> Void
    typealias Clock = @MainActor () -> Date
    typealias Preferences = @MainActor () -> HeartableNotificationPreferences

    private struct MessageKey: Hashable {
        let body: String
        let categoryIdentifier: String
    }

    private let deliver: Delivery
    private let now: Clock
    private let preferences: Preferences
    private var recentMessages: [MessageKey: Date] = [:]

    init(deliver: @escaping Delivery = { notification in
        LocalNotifier.send(
            title: notification.title,
            body: notification.body,
            categoryIdentifier: notification.categoryIdentifier
        )
    }) {
        self.now = { Date() }
        self.preferences = { .read() }
        self.deliver = deliver
    }

    init(preferences: @escaping Preferences, deliver: @escaping Delivery) {
        self.now = { Date() }
        self.preferences = preferences
        self.deliver = deliver
    }

    init(now: @escaping Clock, preferences: @escaping Preferences = { .read() }, deliver: @escaping Delivery) {
        self.now = now
        self.preferences = preferences
        self.deliver = deliver
    }

    func show(
        _ message: String,
        style: Style = .info,
        category: HeartableNotificationCategory? = nil
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Parallel refresh paths can report the same failure at almost the same
        // time. Remember more than the last message so alternating failures do
        // not flood Notification Center. Distinct errors still arrive promptly.
        // An error can never be muted by a caller's routine-event category.
        let identifier = style == .error
            ? style.categoryIdentifier
            : category?.rawValue ?? style.categoryIdentifier
        // Muted feedback must not consume the dedup window. Enabling alerts
        // and immediately retrying an action should allow its first message.
        guard preferences().allows(.resolve(identifier)) else { return }
        let key = MessageKey(body: trimmed, categoryIdentifier: identifier)
        let date = now()
        let cooldown: TimeInterval = style == .error ? 15 : 2
        recentMessages = recentMessages.filter { date.timeIntervalSince($0.value) < 60 }
        if let previous = recentMessages[key], date.timeIntervalSince(previous) < cooldown {
            return
        }
        if recentMessages.count >= 128,
           let oldest = recentMessages.min(by: { $0.value < $1.value })?.key {
            recentMessages.removeValue(forKey: oldest)
        }
        recentMessages[key] = date

        deliver(
            Notification(
                title: "Heartable",
                body: trimmed,
                categoryIdentifier: identifier
            )
        )
    }

    func success(_ message: String, category: HeartableNotificationCategory? = nil) {
        show(message, style: .success, category: category)
    }
    func error(_ message: String) { show(message, style: .error) }
    func info(_ message: String, category: HeartableNotificationCategory? = nil) {
        show(message, style: .info, category: category)
    }
}
