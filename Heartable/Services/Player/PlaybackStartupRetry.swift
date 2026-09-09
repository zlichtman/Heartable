import Foundation

/// Bounded Connect propagation retry after the Spotify SDK has already woken
/// the phone. Authentication, rate-limit and other failures are not retried.
enum PlaybackStartupRetry {
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
