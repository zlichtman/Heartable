import Foundation

/// Bounded Connect propagation retry after the Spotify SDK has already woken
/// the phone. Authentication, rate-limit and other failures are not retried.
enum PlaybackStartupRetry {
    /// An accepted Connect command is not evidence that the selected song is
    /// playing. Verify the song and device before configuring playlist settings.
    @MainActor
    static func confirmSpotifyPlayback(
        uri: String, deviceID: String?, attempts: Int = 3,
        delay: Duration = .milliseconds(400),
        poll: @MainActor () async -> SpotifyAPI.PlaybackPoll
    ) async throws -> PlaybackState {
        for attempt in 0..<max(1, attempts) {
            try Task.checkCancellation()
            let result = await poll()
            try Task.checkCancellation()
            switch result {
            case .state(let state):
                if state.isPlaying == true, state.item?.uri == uri,
                   deviceID == nil || state.device?.id == deviceID {
                    return state
                }
            case .idle: break
            case .rateLimited:
                throw ProviderError("Spotify is limiting player requests. Try again shortly.")
            case .failed:
                // Some phone players accept Play but refuse Connect readback.
                // Let the native SDK establish and confirm playback instead.
                throw SpotifyPlaybackRestrictedError(message: "Spotify couldn’t confirm playback on this device.")
            }
            if attempt + 1 < max(1, attempts) { try await Task.sleep(for: delay) }
        }
        throw NoActiveDeviceError()
    }

    /// A confirmed native start remains successful if optional queue setup fails.
    /// Keep cancellation fatal so superseded taps never publish stale feedback.
    @MainActor
    static func finishNativeHandoff(
        wake: @MainActor () async throws -> Void,
        started: @MainActor () -> Void,
        configureQueue: @MainActor () async throws -> Void,
        queueFailed: @MainActor () -> Void
    ) async throws {
        try await wake()
        try Task.checkCancellation()
        started()
        do {
            try await configureQueue()
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            queueFailed()
        }
    }

    @MainActor
    static func waitForSpotifyDevice(
        attempts: Int = 8,
        delay: Duration = .milliseconds(750),
        install: @MainActor () async throws -> Void
    ) async throws {
        for attempt in 0..<max(1, attempts) {
            try Task.checkCancellation()
            do {
                try await install()
                try Task.checkCancellation()
                return
            } catch is NoActiveDeviceError {
                guard attempt + 1 < max(1, attempts) else { throw NoActiveDeviceError() }
                try await Task.sleep(for: delay)
            }
        }
    }
}
