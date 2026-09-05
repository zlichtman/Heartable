import Foundation
import Observation

/// Pure playback-session state machine used by `NowPlayingSync`. Keeping session
/// qualification separate from backend writes makes privacy and repeat behavior
/// deterministic and testable.
struct ListeningSessionTracker {
    private struct Session {
        let uri: String
        var activeSeconds: TimeInterval = 0
        var lastPositionMs: Int
        var lastObservedAt: Date
        var wasPlaying: Bool
        var suppressed: Bool
        var logged = false
    }

    private var session: Session?

    mutating func observe(
        now: PlayerStore.Now?,
        ghost: Bool,
        at observedAt: Date
    ) -> Bool {
        guard let now, now.source != .radioBrowser else {
            session = nil
            return false
        }

        let repeatedAtStart =
            session?.uri == now.uri
            && now.isPlaying
            && now.positionMs < 8_000
            && (session?.lastPositionMs ?? 0) > 30_000

        if session?.uri != now.uri || repeatedAtStart || session == nil {
            session = Session(
                uri: now.uri,
                lastPositionMs: now.positionMs,
                lastObservedAt: observedAt,
                wasPlaying: now.isPlaying,
                suppressed: ghost
            )
        }

        guard var current = session else { return false }
        current.suppressed = current.suppressed || ghost
        if current.wasPlaying {
            // Cap observation gaps so backgrounding or a network stall cannot
            // manufacture minutes of listening time.
            current.activeSeconds += min(
                max(0, observedAt.timeIntervalSince(current.lastObservedAt)),
                5
            )
        }
        current.lastPositionMs = now.positionMs
        current.lastObservedAt = observedAt
        current.wasPlaying = now.isPlaying
        session = current

        return !current.logged
            && !current.suppressed
            && current.activeSeconds >= 30
    }

    mutating func markLogged() {
        session?.logged = true
    }

    mutating func reset() {
        session = nil
    }
}

/// Pushes the current track to `now_playing` (for the friends feed) and logs a
/// qualified `play_log` row for personal stats. Respects Ghost Mode for the
/// complete playback session, not just individual polling ticks.
@MainActor
@Observable
final class NowPlayingSync {
    private var tracker = ListeningSessionTracker()
    private var logging = false
    private var lastPushAt: Date = .distantPast
    private var clearedUnavailableState = false
    private var lifecycleID = UUID()
    private var suspended = false
    private var activeWrites = 0

    /// A play is counted after 30 seconds of observed playback. Polling,
    /// pause/resume, and seeking stay inside one session; a stop or a true repeat
    /// begins another. A session that starts under Ghost Mode remains suppressed
    /// even if Ghost Mode is turned off before the track ends.
    func sync(now: PlayerStore.Now?, ghost: Bool) async {
        guard !suspended else { return }
        activeWrites += 1
        defer { activeWrites -= 1 }
        guard let ownerID = AccountSessionStore.currentOwnerID else { return }
        let requestID = lifecycleID
        let observedAt = Date()
        let shouldLog = tracker.observe(now: now, ghost: ghost, at: observedAt)

        // Clear once on launch/stop and immediately when Ghost Mode is enabled.
        // The read-side TTL remains the fallback for crashes and failed writes.
        guard let now, !ghost else {
            if !clearedUnavailableState {
                clearedUnavailableState = true
                lastPushAt = .distantPast
                await BackendAPI.shared.clearMyNowPlaying(userID: ownerID)
            }
            return
        }
        clearedUnavailableState = false

        // Throttle now_playing upserts to ~20s.
        if observedAt.timeIntervalSince(lastPushAt) > 18 {
            lastPushAt = observedAt
            await BackendAPI.shared.upsertNowPlaying(
                trackName: now.name, artist: now.artist,
                albumArt: now.artworkURL?.absoluteString, trackUri: now.uri,
                isPlaying: now.isPlaying, progressMs: now.positionMs,
                durationMs: now.durationMs,
                userID: ownerID
            )
            guard owns(ownerID: ownerID, lifecycleID: requestID) else { return }
        }

        if shouldLog, !logging {
            logging = true
            let saved = await BackendAPI.shared.logPlay(
                trackUri: now.uri, trackName: now.name, artist: now.artist,
                durationMs: now.durationMs, albumArt: now.artworkURL?.absoluteString,
                userID: ownerID
            )
            guard owns(ownerID: ownerID, lifecycleID: requestID) else { return }
            logging = false
            if saved { tracker.markLogged() }
        }
    }

    func reset() {
        lifecycleID = UUID()
        tracker.reset()
        logging = false
        lastPushAt = .distantPast
        clearedUnavailableState = false
    }

    func suspendAndWait() async throws {
        suspended = true
        while activeWrites > 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        reset()
    }

    func resume() { suspended = false }

    private func owns(ownerID: UUID, lifecycleID requestID: UUID) -> Bool {
        lifecycleID == requestID
            && AccountSessionStore.currentOwnerID == ownerID
    }
}
