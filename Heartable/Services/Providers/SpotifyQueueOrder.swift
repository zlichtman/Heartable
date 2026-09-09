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

    /// Spotify explicitly does not guarantee execution order across Player API
    /// endpoints. Read the device state back; an accepted PUT alone isn't proof
    /// that native shuffle/repeat can no longer override Heartable's queue.
    static func configure(token: String, deviceID: String?) async throws -> Bool {
        var target = deviceID
        var latest: PlaybackState?
        if case .state(let state) = await SpotifyAPI.pollPlayback(token: token) {
            target = target ?? state.device?.id
            latest = state
            if isConfirmed(state, deviceID: target) { return true }
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
                    // decides whether there is actually anything to warn about.
                }
            }
            try await Task.sleep(for: .milliseconds(attempt == 0 ? 350 : 650))
            switch await SpotifyAPI.pollPlayback(token: token) {
            case .state(let state):
                latest = state
                target = target ?? state.device?.id
                if isConfirmed(state, deviceID: target) { return true }
            case .rateLimited: return false
            default: break
            }
        }
        return latest.map { isConfirmed($0, deviceID: target) } ?? false
    }
}
