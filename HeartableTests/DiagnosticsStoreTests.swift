import XCTest
@testable import Heartable

final class DiagnosticsStoreTests: XCTestCase {
    func testStoreKeepsNewestFirstPrunesAndSurvivesReload() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiagnosticsStore(directory: dir)
        for i in 0..<(DiagnosticsStore.maxEntries + 5) {
            await store.record(kind: "crash", build: "70", summary: "n\(i)", payloadJSON: "{}")
        }
        let entries = await store.entries()
        XCTAssertEqual(entries.count, DiagnosticsStore.maxEntries)
        XCTAssertEqual(entries.first?.summary, "n\(DiagnosticsStore.maxEntries + 4)")
        let reloaded = await DiagnosticsStore(directory: dir).entries()
        XCTAssertEqual(reloaded.map(\.id), entries.map(\.id))
        XCTAssertTrue(reloaded[0].shareText.contains("build 70"))
        await store.clear()
        let cleared = await DiagnosticsStore(directory: dir).entries()
        XCTAssertTrue(cleared.isEmpty)
    }
}
