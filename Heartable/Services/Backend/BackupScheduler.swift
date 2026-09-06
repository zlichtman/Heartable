import Foundation
import SwiftUI

/// Run-if-due scheduler for automatic library backups. There is no background
/// task entitlement in play, so "scheduling" is opportunistic: the app calls
/// `runIfDue()` at launch and on foreground, and this type decides whether a
/// backup is owed based on the persisted frequency preference and the last run
/// date. A first usable library is protected even with a manual cadence. It
/// captures a snapshot the same way
/// the Backups screen's manual capture does, then stamps the run time.
///
/// Reads the same account-scoped keys the Backups screen writes:
/// - `heartable.backup.frequency` (manual / daily / weekly / monthly)
/// Persists its own last-run timestamp under `heartable.backups.lastRun`.
@MainActor
@Observable
final class BackupScheduler {
    /// Key the Backups screen uses for the frequency segmented control.
    private let frequencyKey = "heartable.backup.frequency"
    /// Our own last-successful-run timestamp (epoch seconds).
    private let lastRunKey = "heartable.backups.lastRun"

    /// Shared by scheduled captures, manual captures, and CSV imports.
    private(set) var isRunning = false
    private var suspended = false

    init() {}

    /// Capture the first usable library, then honor the selected cadence.
    /// Empty/disconnected libraries and failed reads remain retryable.
    func runIfDue(userID expectedUserID: UUID? = nil) async {
        guard !isRunning, !suspended, !Task.isCancelled else { return }
        guard let ownerID = AccountSessionStore.currentOwnerID,
              expectedUserID == nil || expectedUserID == ownerID else { return }

        let raw = AccountSessionStore.defaultString(forKey: frequencyKey) ?? "manual"

        // Back up the same services the Backups screen has selected (default: all
        // live services). Disconnected providers read empty, so capture skips them.
        let ids = Self.selectedProviderIDs()
        guard !ids.isEmpty else { return }

        isRunning = true
        defer { isRunning = false }

        do {
            var connected: [ProviderID] = []
            for id in ids where await ProviderRegistry.provider(for: id).isConnected() {
                connected.append(id)
            }
            guard !connected.isEmpty, !Task.isCancelled, !suspended,
                  AccountSessionStore.currentOwnerID == ownerID else { return }
            let initial = try await BackendAPI.shared.needsInitialBackup(userID: ownerID)
            guard Self.shouldCapture(initial: initial, frequency: raw, lastRun: lastRun) else { return }
            guard !Task.isCancelled, !suspended else { return }
            _ = try await BackendAPI.shared.captureSnapshot(
                providerIDs: connected,
                userID: ownerID
            )
            guard AccountSessionStore.currentOwnerID == ownerID else { return }
            try await BackendAPI.shared.markInitialBackupCompleted(userID: ownerID)
            stampLastRun()
            NotificationCenter.default.post(name: .heartableBackupCreated, object: ownerID)
            notifyIfEnabled()
        } catch {
            // Leave lastRun untouched so the next launch retries. Quiet by design.
        }
    }

    /// Live services left selected for backup (`heartable.backup.service.<id>`,
    /// default on) — mirrors the chips on the Backups screen.
    private static func selectedProviderIDs() -> [ProviderID] {
        ProviderCatalog.all
            .filter { $0.section == .library }
            .map(\.id)
            .filter {
                AccountSessionStore.defaultObject(
                    forKey: "heartable.backup.service.\($0.rawValue)"
                ) as? Bool ?? true
            }
    }

    // MARK: - Persistence

    func performManualCapture(
        _ operation: () async throws -> ImportSnapshotResult
    ) async throws -> ImportSnapshotResult {
        guard !suspended, !isRunning else {
            throw BackendError.message("A backup or data cleanup is already running. Try again when it finishes.")
        }
        isRunning = true
        defer { isRunning = false }
        return try await operation()
    }

    /// Finish any in-flight capture before an explicitly requested data clear.
    /// Otherwise its final insert could recreate a backup after deletion.
    func suspendAndWait() async throws {
        suspended = true
        while isRunning {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func resume() { suspended = false }

    private var lastRun: Date? {
        let t = AccountSessionStore.defaultObject(forKey: lastRunKey) as? Double ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private func stampLastRun() {
        AccountSessionStore.setDefault(
            Date().timeIntervalSince1970,
            forKey: lastRunKey
        )
    }

    // MARK: - Notifications (decoupled)

    /// Post a local "Backup complete" notification when the user has opted in.
    /// References `LocalNotifier` directly; it is provided by the notifications
    /// feature and resolves at integration time.
    private func notifyIfEnabled() {
        LocalNotifier.send(title: "Backup complete",
                           body: "Heartable backed up your library.",
                           categoryIdentifier: HeartableNotificationCategory.backupComplete.rawValue)
    }

    // MARK: - Frequency → interval

    static func shouldCapture(initial: Bool, frequency: String, lastRun: Date?, now: Date = Date()) -> Bool {
        if initial { return true }
        guard let interval = interval(for: frequency) else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval
    }

    /// Seconds between scheduled backups for a frequency raw value, or nil if
    /// scheduling is off (manual / unrecognized).
    private static func interval(for raw: String) -> TimeInterval? {
        switch raw {
        case "daily": return 60 * 60 * 24
        case "weekly": return 60 * 60 * 24 * 7
        case "monthly": return 60 * 60 * 24 * 30
        default: return nil
        }
    }
}
