import Foundation
import Observation
import UIKit

/// The single routing point for short-lived app feedback.
///
/// Feature code calls `success` / `error` / `info` (or `show`) and never needs to
/// know how feedback is drawn. Messages surface as one in-app toast rendered by
/// `ToastWindow`, a pass-through overlay window that sits above sheets and
/// full-screen covers. Repeated messages are coalesced so parallel refresh paths
/// reporting the same failure don't stack up, and VoiceOver hears each toast once.
@MainActor
@Observable
final class BannerCenter {
    enum Style: String, Equatable, Sendable {
        case success, error, info
    }

    struct Toast: Identifiable, Equatable, Sendable {
        let id: UUID
        let message: String
        let style: Style
    }

    /// The app-wide instance. Views read it from the environment; non-view
    /// services (e.g. `BackupScheduler`) post through it directly.
    static let shared = BannerCenter()

    /// The toast currently on screen, if any. A newer message replaces it.
    private(set) var current: Toast?

    private struct MessageKey: Hashable {
        let body: String
        let style: Style
    }

    @ObservationIgnored private var recentMessages: [MessageKey: Date] = [:]
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Style = .info) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Parallel refresh paths can report the same failure at almost the same
        // time. Remember more than the last message so alternating failures do
        // not flood the screen. Distinct messages still arrive promptly.
        let key = MessageKey(body: trimmed, style: style)
        let date = Date()
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

        // The same message already on screen just stays up longer instead of
        // re-animating in.
        if let current, current.message == trimmed, current.style == style {
            scheduleDismiss(of: current)
            return
        }

        let toast = Toast(id: UUID(), message: trimmed, style: style)
        current = toast
        announce(toast)
        scheduleDismiss(of: toast)
    }

    func success(_ message: String) { show(message, style: .success) }
    func error(_ message: String) { show(message, style: .error) }
    func info(_ message: String) { show(message, style: .info) }

    /// Remove the toast now. Passing an id only dismisses that toast, so a stale
    /// tap can never clear a newer message.
    func dismiss(_ id: UUID? = nil) {
        guard let current, id == nil || current.id == id else { return }
        dismissTask?.cancel()
        dismissTask = nil
        self.current = nil
    }

    // MARK: - Private

    private func scheduleDismiss(of toast: Toast) {
        dismissTask?.cancel()
        var seconds: Double = toast.style == .error ? 5 : 3.5
        // Give VoiceOver users time to hear the announcement and find the toast.
        if UIAccessibility.isVoiceOverRunning { seconds *= 2 }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    private func announce(_ toast: Toast) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let text = toast.style == .error ? "Error: \(toast.message)" : toast.message
        // Queue behind whatever VoiceOver is currently reading rather than
        // cutting it off mid-sentence.
        let announcement = NSAttributedString(
            string: text,
            attributes: [.accessibilitySpeechQueueAnnouncement: true]
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}
