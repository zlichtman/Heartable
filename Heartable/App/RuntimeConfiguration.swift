import Foundation
import MetricKit
import OSLog

/// Process-wide runtime defaults that should be installed before the first view
/// appears. Keeping this out of `HeartableApp` makes the behavior easy to reuse
/// from previews, future app extensions, and integration tests.
@MainActor
enum RuntimeConfiguration {
    private static var hasConfigured = false

    static func configure() {
        guard !hasConfigured else { return }
        hasConfigured = true

        // Artwork is displayed repeatedly across library, social, and player
        // screens. Give URLSession/AsyncImage a useful shared cache instead of
        // repeatedly downloading the same images as views are recreated.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024
        )

        PerformanceDiagnostics.shared.start()
    }
}

/// Lightweight MetricKit receiver. Production hang, launch, and network metrics
/// are surfaced through unified logging without adding a third-party SDK.
final class PerformanceDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = PerformanceDiagnostics()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Heartable",
        category: "Performance"
    )
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        logger.info("Received \(payloads.count, privacy: .public) MetricKit performance payload(s)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        logger.error("Received \(payloads.count, privacy: .public) MetricKit diagnostic payload(s)")
    }
}

/// Shared signposts for measuring expensive async work in Instruments.
enum PerformanceTrace {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Heartable",
        category: "App"
    )
    static let signposter = OSSignposter(logger: logger)
}
