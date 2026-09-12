import Foundation

enum SpotifyQueueOrder {
    /// Spotify can report an exhausted queue as HTTP 200 with a stopped final
    /// item, not only HTTP 204. A failed poll or an ordinary mid-song pause is
    /// never an end signal.
    static func didFinishSegment(previous: PlayerStore.Now, state: PlaybackState?,
                                 wasIdle: Bool, elapsed: TimeInterval) -> Bool {
        guard previous.isPlaying, previous.durationMs > 0,
              Double(previous.positionMs) + max(0, min(elapsed, 10)) * 1_000
                >= Double(previous.durationMs - 500) else { return false }
        if wasIdle { return true }
        guard let state, state.isPlaying == false,
              state.item == nil || state.item?.uri == previous.uri else { return false }
        let position = state.progressMs ?? previous.durationMs
        return position >= previous.durationMs - 750 || position <= 1_000
    }

    static func isConfirmed(_ state: PlaybackState, deviceID: String?) -> Bool {
        state.shuffleState == false && state.repeatState == "off"
            && (deviceID == nil || state.device?.id == deviceID)
    }

    static func controlPath(_ setting: String, value: String, deviceID: String?) -> String {
        var components = URLComponents()
        components.path = "/me/player/\(setting)"
        components.queryItems = [URLQueryItem(name: "state", value: value)]
        if let deviceID { components.queryItems?.append(URLQueryItem(name: "device_id", value: deviceID)) }
        return components.string ?? "/me/player/\(setting)?state=\(value)"
    }

    /// Why the device still isn't in Heartable's plain-order mode, in user
    /// words: Spotify's refusal of a command, or what the readback reported.
    enum Verification: Equatable, Sendable {
        case confirmed
        case unconfirmed(String)

        var isConfirmed: Bool { self == .confirmed }
    }

    static func describeUnconfirmed(state: PlaybackState?, deviceID: String?, refusal: String?) -> String {
        if let refusal { return "Spotify refused to change the playback mode: \(refusal)" }
        guard let state else { return "Spotify didn’t report the device state." }
        var parts: [String] = []
        if state.shuffleState == true {
            parts.append("Shuffle is still on (Spotify’s Smart Shuffle can’t be turned off from another app)")
        }
        if let repeatState = state.repeatState, repeatState != "off" {
            parts.append("Repeat is still \(repeatState)")
        }
        if let deviceID, let reported = state.device?.id, reported != deviceID {
            parts.append("playback is on a different device (\(state.device?.name ?? "unknown"))")
        }
        return parts.isEmpty ? "Spotify didn’t confirm the playback mode." : parts.joined(separator: "; ") + "."
    }

    /// Spotify explicitly does not guarantee execution order across Player API
    /// endpoints. Read the device state back; an accepted PUT alone isn't proof
    /// that native shuffle/repeat can no longer override Heartable's queue.
    static func configure(token: String, deviceID: String?) async throws -> Bool {
        try await verify(token: token, deviceID: deviceID).isConfirmed
    }

    static func verify(token: String, deviceID: String?) async throws -> Verification {
        var target = deviceID
        var latest: PlaybackState?
        var refusal: String?
        if case .state(let state) = await SpotifyAPI.pollPlayback(token: token) {
            target = target ?? state.device?.id
            latest = state
            if isConfirmed(state, deviceID: target) { return .confirmed }
        }
        for attempt in 0..<2 {
            try Task.checkCancellation()
            // Pin every setting to the same device that received Play.
            for (setting, value) in [("shuffle", "false"), ("repeat", "off")] {
                do {
                    try await SpotifyAPI.control(controlPath(setting, value: value, deviceID: target), token: token)
                } catch {
                    try Task.checkCancellation()
                    // A command can fail after the device applied it. Readback
                    // decides whether there is anything to warn about; keep the
                    // reason so the warning can name it.
                    refusal = error.localizedDescription
                }
            }
            try await Task.sleep(for: .milliseconds(attempt == 0 ? 350 : 650))
            switch await SpotifyAPI.pollPlayback(token: token) {
            case .state(let state):
                latest = state
                target = target ?? state.device?.id
                if isConfirmed(state, deviceID: target) { return .confirmed }
            case .rateLimited:
                return .unconfirmed("Spotify is limiting player requests; try again in a moment.")
            default: break
            }
        }
        if let latest, isConfirmed(latest, deviceID: target) { return .confirmed }
        return .unconfirmed(describeUnconfirmed(state: latest, deviceID: target, refusal: refusal))
    }
}
