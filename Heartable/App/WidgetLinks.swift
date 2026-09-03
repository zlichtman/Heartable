import Foundation
import Observation

/// Retains a cold-launch widget tap until the authenticated shell is ready.
@MainActor @Observable
final class WidgetLinks {
    private(set) var pending: HeartableWidgetRoute?
    private(set) var requestID: UUID?

    func handle(_ url: URL) {
        guard let route = HeartableWidgetRoute(url: url) else { return }
        pending = route
        requestID = UUID()
    }

    func take() -> HeartableWidgetRoute? {
        defer { pending = nil }
        return pending
    }

    func reset() {
        pending = nil
        requestID = nil
    }
}
