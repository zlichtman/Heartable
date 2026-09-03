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

    private let deliver: Delivery
    private var lastMessage: String?
    private var lastDeliveryDate = Date.distantPast

    init(deliver: @escaping Delivery = { notification in
        LocalNotifier.send(
            title: notification.title,
            body: notification.body,
            categoryIdentifier: notification.categoryIdentifier
        )
    }) {
        self.deliver = deliver
    }

    func show(_ message: String, style: Style = .info) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Parallel refresh paths can report the same failure at almost the same
        // time. Avoid asking iOS to stack duplicate native notifications.
        let now = Date()
        if lastMessage == trimmed, now.timeIntervalSince(lastDeliveryDate) < 1.5 {
            return
        }
        lastMessage = trimmed
        lastDeliveryDate = now

        deliver(
            Notification(
                title: "Heartable",
                body: trimmed,
                categoryIdentifier: style.categoryIdentifier
            )
        )
    }

    func success(_ message: String) { show(message, style: .success) }
    func error(_ message: String) { show(message, style: .error) }
    func info(_ message: String) { show(message, style: .info) }
}
