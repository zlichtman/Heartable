import XCTest
@testable import Heartable

/// The watchdog reports Heartable received carry no app frames, so the app
/// records its own evidence while the main thread is unresponsive.
@MainActor
final class MainThreadStallMonitorTests: XCTestCase {
    func testBlockedMainThreadRecordsBreadcrumbsAndStackSamples() async throws {
        #if !arch(arm64)
        throw XCTSkip("Main-thread sampling is implemented for arm64")
        #else
        // The host app starts the shared monitor at launch; starting is idempotent.
        MainThreadStallMonitor.shared.start()
        let marker = "stall-test-\(UUID().uuidString.prefix(8))"
        MainThreadStallMonitor.note(marker)
        // Let the monitor exchange at least one ping with a responsive main thread.
        try await Task.sleep(for: .milliseconds(1_500))

        blockMainThread(seconds: 3.4)

        var stall: DiagnosticEntry?
        for _ in 0..<40 where stall == nil {
            try await Task.sleep(for: .milliseconds(250))
            stall = await DiagnosticsStore.shared.entries()
                .first { $0.kind == "stall" && $0.payloadJSON.contains(marker) }
        }
        let entry = try XCTUnwrap(stall, "A 3.4 s main-thread block must be recorded")
        XCTAssertTrue(entry.summary.contains("then recovered"), entry.summary)

        let payload = try JSONDecoder().decode(StallPayload.self, from: Data(entry.payloadJSON.utf8))
        XCTAssertGreaterThanOrEqual(payload.seconds, MainThreadStallMonitor.stallThreshold)
        XCTAssertTrue(payload.recovered)
        XCTAssertTrue(payload.breadcrumbs.contains { $0.hasSuffix(marker) })
        let sample = try XCTUnwrap(payload.samples.first, "The blocked main thread must be sampled")
        XCTAssertGreaterThan(sample.count, 3, "A sample needs more than the program counter")
        XCTAssertTrue(payload.samples.joined().contains { $0.hasPrefix("HeartableTests") || $0.hasPrefix("Heartable") },
                      "Samples must reach the app's own frames")
        #endif
    }

    func testSummaryNamesOutcomeAndLatestBreadcrumbs() {
        let stall = MainThreadStallMonitor.PendingStall(
            build: "95", startedAt: Date(), seconds: 9.6, recovered: false, footprintMB: 410,
            breadcrumbs: ["-12.0s tab library", "-9.8s open playlist (3000 songs, library)", "-9.7s playlist landscape"],
            samples: [])
        let summary = MainThreadStallMonitor.summary(for: stall)
        XCTAssertTrue(summary.contains("9.6 s"))
        XCTAssertTrue(summary.contains("app ended before it recovered"))
        XCTAssertTrue(summary.contains("open playlist (3000 songs, library)"))
    }

    /// Synchronously occupies the main thread, as a runaway SwiftUI update would.
    private func blockMainThread(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private struct StallPayload: Decodable {
        let seconds: Double
        let recovered: Bool
        let breadcrumbs: [String]
        let samples: [[String]]
    }
}
