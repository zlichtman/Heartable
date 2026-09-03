import Foundation
import Observation

enum GhostModeDuration: String, CaseIterable, Sendable, Identifiable {
    case oneHour
    case eightHours
    case untilTomorrow
    case indefinite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour: "1 hour"
        case .eightHours: "8 hours"
        case .untilTomorrow: "Until tomorrow"
        case .indefinite: "Until I turn it off"
        }
    }

    var detail: String {
        switch self {
        case .oneHour: "Resume recording in one hour"
        case .eightHours: "Resume recording in eight hours"
        case .untilTomorrow: "Resume at midnight"
        case .indefinite: "No automatic expiry"
        }
    }

    var systemImage: String {
        switch self {
        case .oneHour: "clock"
        case .eightHours: "moon.stars.fill"
        case .untilTomorrow: "sunrise.fill"
        case .indefinite: "infinity"
        }
    }

    func expiration(
        startingAt date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .oneHour:
            date.addingTimeInterval(60 * 60)
        case .eightHours:
            date.addingTimeInterval(8 * 60 * 60)
        case .untilTomorrow:
            calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: date)
            ) ?? date.addingTimeInterval(24 * 60 * 60)
        case .indefinite:
            nil
        }
    }
}

/// Shuffle mode + ghost mode + per-song weights. Mode/ghost persist locally;
/// weights sync from `track_weights` (wired in Phase 7). Ported from the RN
/// PlaybackPrefsContext.
@MainActor
@Observable
final class PlaybackPrefsStore {
    private static let modeKey = "heartable_shuffle_mode"
    private static let ghostKey = "heartable_ghost_mode"
    private static let ghostUntilKey = "heartable_ghost_mode_until"

    var mode: ShuffleMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
    }

    private(set) var ghostModeUntil: Date?
    private(set) var ghostModeIndefinite: Bool

    /// Compatibility surface for existing playback/capture call sites. Directly
    /// assigning `true` preserves the legacy indefinite behavior.
    var ghostMode: Bool {
        get { isGhostModeEnabled() }
        set {
            if newValue {
                enableGhostMode(for: .indefinite)
            } else {
                disableGhostMode()
            }
        }
    }

    /// uri → weight in [-100, 100]. Populated from the backend in Phase 7.
    private(set) var weights: [String: Int] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ghostExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var weightWriteTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lifecycleID = UUID()

    init(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.modeKey)
        mode = raw.flatMap(ShuffleMode.init(rawValue:)) ?? .order
        let storedEnabled = defaults.bool(forKey: Self.ghostKey)
        let storedUntil = defaults.object(forKey: Self.ghostUntilKey) as? Date
        ghostModeUntil = storedEnabled ? storedUntil : nil
        // A true legacy boolean with no expiry is the former indefinite mode.
        ghostModeIndefinite = storedEnabled && storedUntil == nil

        if let storedUntil, (!storedEnabled || storedUntil <= now) {
            ghostModeUntil = nil
            ghostModeIndefinite = false
            persistGhostMode()
        } else {
            scheduleGhostExpiration(now: now)
        }
    }

    deinit {
        ghostExpirationTask?.cancel()
    }

    func enableGhostMode(
        for duration: GhostModeDuration,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        ghostModeIndefinite = duration == .indefinite
        ghostModeUntil = duration.expiration(
            startingAt: now,
            calendar: calendar
        )
        persistGhostMode()
        scheduleGhostExpiration(now: now)
    }

    func disableGhostMode() {
        ghostExpirationTask?.cancel()
        ghostExpirationTask = nil
        ghostModeIndefinite = false
        ghostModeUntil = nil
        persistGhostMode()
    }

    func isGhostModeEnabled(at now: Date = Date()) -> Bool {
        ghostModeIndefinite
            || ghostModeUntil.map { $0 > now } == true
    }

    /// Reconcile wall-clock changes, foreground wakeups, and timers suspended by
    /// iOS. Expired state is cleared from memory and persistence immediately.
    func refreshGhostMode(now: Date = Date()) {
        if let until = ghostModeUntil, until <= now {
            disableGhostMode()
        } else {
            scheduleGhostExpiration(now: now)
        }
    }

    func ghostModeStatus(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if ghostModeIndefinite { return "On until you turn it off" }
        guard let until = ghostModeUntil, until > now else {
            return "Plays are being recorded"
        }
        if calendar.isDateInTomorrow(until) {
            let components = calendar.dateComponents(
                [.hour, .minute, .second],
                from: until
            )
            if components.hour == 0,
               components.minute == 0,
               components.second == 0 {
                return "On until tomorrow"
            }
            return "On until tomorrow at \(until.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDate(until, inSameDayAs: now) {
            return "On until \(until.formatted(date: .omitted, time: .shortened))"
        }
        return "On until \(until.formatted(date: .abbreviated, time: .shortened))"
    }

    private func persistGhostMode() {
        let enabled = ghostModeIndefinite || ghostModeUntil != nil
        defaults.set(enabled, forKey: Self.ghostKey)
        if let ghostModeUntil {
            defaults.set(ghostModeUntil, forKey: Self.ghostUntilKey)
        } else {
            defaults.removeObject(forKey: Self.ghostUntilKey)
        }
    }

    private func scheduleGhostExpiration(now: Date = Date()) {
        ghostExpirationTask?.cancel()
        ghostExpirationTask = nil
        guard !ghostModeIndefinite, let until = ghostModeUntil else { return }
        let delay = max(0, until.timeIntervalSince(now))
        ghostExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshGhostMode()
        }
    }

    /// Advance the playback mode order -> shuffle -> weighted -> order. Persists via
    /// `mode`'s observer. Additive convenience for tap-to-cycle controls.
    func cycleMode() { mode = mode.next }

    func setWeights(_ w: [String: Int]) { weights = w }

    /// Forget per-song weights (call on sign-out / delete / account switch).
    /// Mode/ghost are device-level prefs and are intentionally left intact.
    func reset() {
        lifecycleID = UUID()
        for task in weightWriteTasks.values { task.cancel() }
        weightWriteTasks = [:]
        weights = [:]
    }

    func order(_ uris: [String]) -> [String] {
        orderForPlayback(uris, mode: mode, weights: weights)
    }

    func weight(for uri: String) -> Int { weights[uri] ?? 0 }

    /// Load per-song weights from the backend (call after sign-in).
    func loadWeights() async {
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            weights = [:]
            return
        }
        let requestID = lifecycleID
        let rows = await BackendAPI.shared.getMyWeights(userID: ownerID)
        guard lifecycleID == requestID,
              AccountSessionStore.currentOwnerID == ownerID else { return }
        var map: [String: Int] = [:]
        for r in rows { map[r.trackUri] = Int(r.weight.rounded()) }
        weights = map
    }

    /// Set an absolute weight, clamped to [-100, 100], and persist.
    func setWeight(_ uri: String, to value: Int) {
        let clamped = max(-100, min(100, value))
        weights[uri] = clamped
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        let requestID = lifecycleID
        weightWriteTasks[uri]?.cancel()
        weightWriteTasks[uri] = Task { @MainActor [weak self] in
            guard let self,
                  self.lifecycleID == requestID,
                  AccountSessionStore.currentOwnerID == ownerID else { return }
            try? await BackendAPI.shared.setTrackWeight(
                uri: uri,
                weight: Double(clamped),
                userID: ownerID
            )
            guard self.lifecycleID == requestID else { return }
            self.weightWriteTasks[uri] = nil
        }
    }

    /// Boost (+10) / downvote (-10) relative to the current weight.
    func bump(_ uri: String, by delta: Int) {
        setWeight(uri, to: weight(for: uri) + delta)
    }
}
