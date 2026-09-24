import XCTest
@testable import Heartable

actor ControlledLoads {
    private var pending: [String: CheckedContinuation<String, Never>] = [:]
    private(set) var started: [String] = []
    private(set) var cancelled: Set<String> = []
    private(set) var peak = 0

    func run(_ key: String) async -> String {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return key }
            return await withCheckedContinuation { continuation in
                pending[key] = continuation
                started.append(key)
                peak = max(peak, pending.count)
            }
        } onCancel: {
            Task { await self.cancel(key) }
        }
    }
    func finish(_ key: String) { pending.removeValue(forKey: key)?.resume(returning: key) }
    func cancel(_ key: String) { cancelled.insert(key); finish(key) }
}

@MainActor
final class SharedLoadSchedulerTests: XCTestCase {
    private func eventually(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for scheduler", file: file, line: line)
    }

    func testOneConsumerCanLeaveWithoutCancellingSharedWork() async {
        let pool = SharedLoadScheduler<String, String>(limit: 2)
        let source = ControlledLoads()
        let first = Task { await pool.value(for: "a") { await source.run("a") } }
        await eventually { await source.started.count == 1 }
        let second = Task { await pool.value(for: "a") { await source.run("unexpected") } }
        // Ensure the second subscription is registered before releasing the first.
        await eventually { await pool.subscriberCount(for: "a") == 2 }
        first.cancel()
        let firstResult = await first.value
        XCTAssertNil(firstResult)
        let cancelled = await source.cancelled
        XCTAssertTrue(cancelled.isEmpty)
        await source.finish("a")
        let secondResult = await second.value
        XCTAssertEqual(secondResult, "a")
        let starts = await source.started
        XCTAssertEqual(starts, ["a"])
    }

    func testLastConsumerCancelsOperationAndReleasesSlot() async {
        let pool = SharedLoadScheduler<String, String>(limit: 1)
        let source = ControlledLoads()
        let first = Task { await pool.value(for: "a") { await source.run("a") } }
        await eventually { await source.started.count == 1 }
        first.cancel()
        let result = await first.value
        XCTAssertNil(result)
        await eventually { await source.cancelled.contains("a") }
        let next = Task { await pool.value(for: "b") { await source.run("b") } }
        await eventually { await source.started.contains("b") }
        await source.finish("b")
        _ = await next.value
        let peak = await source.peak
        XCTAssertEqual(peak, 1)
    }

    func testVisibleRequestRunsBeforeQueuedIndexingWithinGlobalLimit() async {
        let pool = SharedLoadScheduler<String, String>(limit: 1)
        let source = ControlledLoads()
        let a = Task { await pool.value(for: "a") { await source.run("a") } }
        await eventually { await source.started.count == 1 }
        let b = Task { await pool.value(for: "b") { await source.run("b") } }
        let c = Task { await pool.value(for: "c", priority: 1) { await source.run("c") } }
        await eventually {
            let bCount = await pool.subscriberCount(for: "b")
            let cCount = await pool.subscriberCount(for: "c")
            return bCount == 1 && cCount == 1
        }
        await source.finish("a")
        await eventually { await source.started.count == 2 }
        let starts = await source.started
        XCTAssertEqual(starts, ["a", "c"])
        b.cancel()
        await source.finish("c")
        _ = await a.value; _ = await b.value; _ = await c.value
        let finalStarts = await source.started
        XCTAssertEqual(finalStarts, ["a", "c"])
    }
}
