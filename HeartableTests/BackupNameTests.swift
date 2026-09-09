import XCTest
@testable import Heartable

final class BackupNameTests: XCTestCase {
    @MainActor
    func testDataClearSuspensionBlocksManualCaptureUntilResumed() async throws {
        let scheduler = BackupScheduler()
        try await scheduler.suspendAndWait()
        var attempted = false
        do {
            _ = try await scheduler.performManualCapture {
                attempted = true
                return .init(snapshotID: UUID(), playlistCount: 1, trackCount: 1, likedCount: 0)
            }
            XCTFail("Suspended capture was accepted")
        } catch { }
        XCTAssertFalse(attempted)
        scheduler.resume()
        let result = try await scheduler.performManualCapture {
            .init(snapshotID: UUID(), playlistCount: 1, trackCount: 1, likedCount: 0)
        }
        XCTAssertEqual(result.trackCount, 1)
        XCTAssertFalse(scheduler.isRunning)
    }

    @MainActor
    func testFailedManualCaptureReleasesItsLock() async {
        let scheduler = BackupScheduler()
        do {
            _ = try await scheduler.performManualCapture {
                throw BackendError.message("Fixture failure")
            }
            XCTFail("Failure was swallowed")
        } catch { }
        XCTAssertFalse(scheduler.isRunning)
    }

    @MainActor
    func testInitialBackupPrecedesManualCadenceWithoutRepeatingIt() {
        XCTAssertTrue(BackupScheduler.shouldCapture(initial: true, frequency: "manual", lastRun: nil))
        XCTAssertFalse(BackupScheduler.shouldCapture(initial: false, frequency: "manual", lastRun: nil))
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertFalse(BackupScheduler.shouldCapture(initial: false, frequency: "daily", lastRun: now, now: now))
        XCTAssertTrue(BackupScheduler.shouldCapture(initial: false, frequency: "daily", lastRun: now.addingTimeInterval(-86_400), now: now))
    }

    func testDefaultIsOnlyLocalizedDateAndTime() {
        let date = Date(timeIntervalSince1970: 0)
        let locale = Locale(identifier: "en_US")
        let zone = TimeZone(secondsFromGMT: 0)!
        let name = BackupName.timestamp(date, locale: locale, timeZone: zone)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        XCTAssertEqual(name, formatter.string(from: date))
        XCTAssertTrue(name.contains("1970"))
        XCTAssertFalse(name.localizedCaseInsensitiveContains("backup"))
    }

    func testDefaultUsesRequestedLocalTimeZone() {
        let date = Date(timeIntervalSince1970: 0)
        let locale = Locale(identifier: "en_GB")
        XCTAssertNotEqual(
            BackupName.timestamp(date, locale: locale, timeZone: TimeZone(secondsFromGMT: 0)!),
            BackupName.timestamp(date, locale: locale, timeZone: TimeZone(secondsFromGMT: -21_600)!)
        )
    }

    func testRenameTrimsWhitespaceAndPreservesUserText() throws {
        XCTAssertEqual(try BackupName.validated("  Road trip ♥︎\n"), "Road trip ♥︎")
        XCTAssertEqual(try BackupName.validated(String(repeating: "a", count: 120)).count, 120)
    }

    func testRenameRejectsEmptyAndOversizedNames() {
        XCTAssertThrowsError(try BackupName.validated(" \n\t"))
        XCTAssertThrowsError(try BackupName.validated(String(repeating: "a", count: 121)))
    }
}
