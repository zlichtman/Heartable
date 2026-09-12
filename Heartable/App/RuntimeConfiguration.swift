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
        // Memory-limit and watchdog terminations never produce a crash log, so
        // the daily exit counts are the only trace they leave. Keep the days
        // that had any, with the peak memory, so a tester can show them.
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics else { continue }
            let fg = exits.foregroundExitData
            let bg = exits.backgroundExitData
            let counts: [(String, Int)] = [
                ("foreground memory limit", fg.cumulativeMemoryResourceLimitExitCount),
                ("foreground watchdog", fg.cumulativeAppWatchdogExitCount),
                ("foreground bad access", fg.cumulativeBadAccessExitCount),
                ("foreground illegal instruction", fg.cumulativeIllegalInstructionExitCount),
                ("foreground abnormal", fg.cumulativeAbnormalExitCount),
                ("background memory limit", bg.cumulativeMemoryResourceLimitExitCount),
                ("background memory pressure", bg.cumulativeMemoryPressureExitCount),
                ("background watchdog", bg.cumulativeAppWatchdogExitCount),
            ].filter { $0.1 > 0 }
            guard !counts.isEmpty else { continue }
            let peak = payload.memoryMetrics?.peakMemoryUsage
                .converted(to: .megabytes).value
            var summary = counts.map { "\($0.0): \($0.1)" }.joined(separator: ", ")
            if let peak { summary += String(format: "; peak memory %.0f MB", peak) }
            let build = payload.latestApplicationVersion
            let json = String(decoding: payload.jsonRepresentation(), as: UTF8.self)
            Task { await DiagnosticsStore.shared.record(kind: "exits", build: build, summary: summary, payloadJSON: json) }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        logger.error("Received \(payloads.count, privacy: .public) MetricKit diagnostic payload(s)")
        for payload in payloads {
            let json = String(decoding: payload.jsonRepresentation(), as: UTF8.self)
            for crash in payload.crashDiagnostics ?? [] {
                var parts: [String] = []
                if let type = crash.exceptionType { parts.append("exception \(type)") }
                if let signal = crash.signal { parts.append("signal \(signal)") }
                if let reason = crash.terminationReason { parts.append(reason) }
                let summary = parts.isEmpty ? "Crash" : parts.joined(separator: ", ")
                let build = crash.metaData.applicationBuildVersion
                Task { await DiagnosticsStore.shared.record(kind: "crash", build: build, summary: summary, payloadJSON: json) }
            }
            for hang in payload.hangDiagnostics ?? [] {
                let seconds = hang.hangDuration.converted(to: .seconds).value
                let summary = String(format: "Main thread hung for %.1f s", seconds)
                let build = hang.metaData.applicationBuildVersion
                Task { await DiagnosticsStore.shared.record(kind: "hang", build: build, summary: summary, payloadJSON: json) }
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                let summary = String(format: "Excessive CPU: %.1f s", cpu.totalCPUTime.converted(to: .seconds).value)
                let build = cpu.metaData.applicationBuildVersion
                Task { await DiagnosticsStore.shared.record(kind: "cpu", build: build, summary: summary, payloadJSON: json) }
            }
            for disk in payload.diskWriteExceptionDiagnostics ?? [] {
                let summary = String(format: "Excessive disk writes: %.0f MB", disk.totalWritesCaused.converted(to: .megabytes).value)
                let build = disk.metaData.applicationBuildVersion
                Task { await DiagnosticsStore.shared.record(kind: "diskWrite", build: build, summary: summary, payloadJSON: json) }
            }
        }
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
