import XCTest
@testable import Heartable

@MainActor
final class HeartableNotificationTests: XCTestCase {
    func testFeedbackRoutesToAppleNotificationDelivery() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter(preferences: { .init() }) { delivered.append($0) }

        center.success("Profile saved")
        center.error("Couldn’t refresh library")

        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered[0].title, "Heartable")
        XCTAssertEqual(delivered[0].body, "Profile saved")
        XCTAssertEqual(delivered[0].categoryIdentifier, "heartable.feedback.success")
        XCTAssertEqual(delivered[1].categoryIdentifier, "heartable.feedback.error")
    }

    func testDuplicateFeedbackIsCoalesced() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter(preferences: { .init() }) { delivered.append($0) }

        center.info("Already connected")
        center.info("Already connected")

        XCTAssertEqual(delivered.count, 1)
    }

    func testBlankFeedbackIsNotDelivered() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter(preferences: { .init() }) { delivered.append($0) }

        center.info("  \n ")

        XCTAssertTrue(delivered.isEmpty)
    }

    func testAlternatingFailuresDoNotFloodNotificationCenter() {
        var delivered: [BannerCenter.Notification] = []
        var date = Date(timeIntervalSince1970: 1_000)
        let center = BannerCenter(now: { date }, preferences: { .init() }) { delivered.append($0) }

        center.error("Couldn’t refresh friends")
        center.error("Couldn’t refresh library")
        date.addTimeInterval(5)
        center.error("Couldn’t refresh friends")
        center.error("Couldn’t refresh library")
        XCTAssertEqual(delivered.count, 2)

        date.addTimeInterval(11)
        center.error("Couldn’t refresh library")
        XCTAssertEqual(delivered.count, 3)
    }

    func testAnEarlierInfoMessageCannotHideAnActionableError() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter(preferences: { .init() }) { delivered.append($0) }

        center.info("Spotify needs attention")
        center.error("Spotify needs attention")

        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last?.categoryIdentifier, "heartable.feedback.error")
    }

    func testUnmutingImmediatelyAllowsPreviouslyMutedFeedback() {
        var delivered: [BannerCenter.Notification] = []
        var preferences = HeartableNotificationPreferences()
        preferences.allow = false
        let center = BannerCenter(preferences: { preferences }) { delivered.append($0) }

        center.error("Couldn’t refresh library")
        XCTAssertTrue(delivered.isEmpty)
        preferences.allow = true
        center.error("Couldn’t refresh library")
        XCTAssertEqual(delivered.count, 1)

        preferences.actionUpdates = false
        center.success("Profile saved")
        XCTAssertEqual(delivered.count, 1)
        preferences.actionUpdates = true
        center.success("Profile saved")
        XCTAssertEqual(delivered.count, 2)
    }

    func testFailureCannotBeMisclassifiedIntoAMutedCategory() {
        var delivered: [BannerCenter.Notification] = []
        let center = BannerCenter(preferences: { .init() }) { delivered.append($0) }

        center.success("Backup complete", category: .backupComplete)
        center.show("Backup failed", style: .error, category: .backupComplete)

        XCTAssertEqual(delivered[0].categoryIdentifier, HeartableNotificationCategory.backupComplete.rawValue)
        XCTAssertEqual(delivered[1].categoryIdentifier, HeartableNotificationCategory.attentionNeeded.rawValue)
    }

    func testRoutineMuteDoesNotMuteErrorsOrAutomaticBackups() {
        var preferences = HeartableNotificationPreferences()
        preferences.actionUpdates = false

        XCTAssertFalse(preferences.allows(.actionUpdates))
        XCTAssertTrue(preferences.allows(.attentionNeeded))
        XCTAssertTrue(preferences.allows(.backupComplete))
        XCTAssertFalse(preferences.allows(.weeklyReminder))
    }

    func testAutomaticBackupMuteDoesNotMuteManualActionResultsOrErrors() {
        var preferences = HeartableNotificationPreferences()
        preferences.backupComplete = false

        XCTAssertFalse(preferences.allows(.backupComplete))
        XCTAssertTrue(preferences.allows(.actionUpdates))
        XCTAssertTrue(preferences.allows(.attentionNeeded))
    }

    func testMasterOffWinsOverEveryCategoryAndSound() {
        var preferences = HeartableNotificationPreferences()
        preferences.allow = false
        preferences.weeklyReminder = true

        for category in [HeartableNotificationCategory.attentionNeeded, .actionUpdates, .backupComplete, .weeklyReminder] {
            XCTAssertFalse(preferences.allows(category))
            XCTAssertFalse(preferences.playsSound(for: category))
            XCTAssertTrue(LocalNotifier.foregroundOptions(
                categoryIdentifier: category.rawValue,
                preferences: preferences
            ).isEmpty)
        }
    }

    func testRoutineUpdatesAreSilentAndSoundSwitchDoesNotMuteErrors() {
        var preferences = HeartableNotificationPreferences()
        XCTAssertFalse(preferences.playsSound(for: .actionUpdates))
        XCTAssertTrue(preferences.playsSound(for: .attentionNeeded))

        preferences.sounds = false
        XCTAssertFalse(preferences.playsSound(for: .attentionNeeded))
        let options = LocalNotifier.foregroundOptions(
            categoryIdentifier: "heartable.feedback.error",
            preferences: preferences
        )
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.list))
        XCTAssertFalse(options.contains(.sound))
    }

    func testForegroundPresentationRechecksCurrentRoutinePreference() {
        var preferences = HeartableNotificationPreferences()
        preferences.actionUpdates = false

        for identifier in ["heartable.general", "heartable.feedback.success", "heartable.feedback.info"] {
            XCTAssertTrue(LocalNotifier.foregroundOptions(
                categoryIdentifier: identifier,
                preferences: preferences
            ).isEmpty)
        }
        XCTAssertFalse(LocalNotifier.foregroundOptions(
            categoryIdentifier: "heartable.feedback.error",
            preferences: preferences
        ).isEmpty)
    }

    func testWeeklyReminderIsOptInAndPreservesAnExistingExplicitChoice() throws {
        let suiteName = "HeartableNotificationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = HeartableNotificationPreferences.read(from: defaults)
        XCTAssertTrue(initial.allow)
        XCTAssertFalse(initial.weeklyReminder)

        defaults.set(true, forKey: "heartable.notifications.weeklyLeaderboard")
        defaults.set(false, forKey: "heartable.notifications.backupComplete")
        let existing = HeartableNotificationPreferences.read(from: defaults)
        XCTAssertTrue(existing.weeklyReminder)
        XCTAssertFalse(existing.backupComplete)
    }
}
