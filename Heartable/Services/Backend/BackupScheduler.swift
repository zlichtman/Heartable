import Foundation
import SwiftUI

/// Run-if-due scheduler for automatic library backups. There is no background
/// task entitlement in play, so "scheduling" is opportunistic: the app calls
/// `runIfDue()` at launch and on foreground, and this type decides whether a
/// backup is owed based on the persisted frequency preference and the last run
/// date. When due (and Spotify is connected), it captures a snapshot the same way
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
    /// Notification opt-in the Notifications screen writes.
    private let notifyKey = "heartable.notifications.backupComplete"

    /// True while a scheduled capture is in flight, to coalesce launch+foreground.
    private(set) var isRunning = false

    init() {}

    /// Capture a snapshot if one is due. No-ops quietly when the frequency is
    /// manual, the interval has not elapsed, Spotify is not connected, or a run is
    /// already in flight. Safe to call on every launch and foreground.
    func runIfDue(userID expectedUserID: UUID? = nil) async {
        guard !isRunning else { return }
        guard let ownerID = AccountSessionStore.currentOwnerID,
              expectedUserID == nil || expectedUserID == ownerID else { return }

        let raw = AccountSessionStore.defaultString(forKey: frequencyKey) ?? "manual"
        guard let interval = Self.interval(for: raw) else { return } // manual / unknown → off

        let last = lastRun
        if let last, Date().timeIntervalSince(last) < interval { return } // not due yet

        // Back up the same services the Backups screen has selected (default: all
        // live services). Disconnected providers read empty, so capture skips them.
        let ids = Self.selectedProviderIDs()
        guard !ids.isEmpty else { return }

        isRunning = true
        defer { isRunning = false }

        do {
            _ = try await BackendAPI.shared.captureSnapshot(
                providerIDs: ids,
                userID: ownerID
            )
            guard AccountSessionStore.currentOwnerID == ownerID else { return }
            stampLastRun()
            notifyIfEnabled()
        } catch {
            // Leave lastRun untouched so the next launch retries. Quiet by design.
        }
    }

    /// Live services left selected for backup (`heartable.backup.service.<id>`,
    /// default on) — mirrors the chips on the Backups screen.
    private static func selectedProviderIDs() -> [ProviderID] {
        ProviderCatalog.all
            .filter { $0.status == .live }
            .map(\.id)
            .filter {
                AccountSessionStore.defaultObject(
                    forKey: "heartable.backup.service.\($0.rawValue)"
                ) as? Bool ?? true
            }
    }

    // MARK: - Persistence

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
        let enabled = UserDefaults.standard.object(forKey: notifyKey) as? Bool ?? true
        guard enabled else { return }
        LocalNotifier.send(title: "Backup complete",
                           body: "Heartable backed up your library.")
    }

    // MARK: - Frequency → interval

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
