import Foundation
import os

/// Keeps a launch from inheriting library caches that the running build cannot
/// trust.
///
/// Two situations discard the derived library caches before any of them are
/// decoded. Identity, provider pairings, Keychain credentials, backups and
/// appearance are never touched; the caches are re-derived from the providers.
///
/// 1. **A different build.** The first launch after an update starts clean, so
///    a snapshot written by an older build can never crash a newer one, and a
///    crash loop cannot survive a TestFlight update.
/// 2. **An abnormal end during bootstrap.** A marker is raised when library
///    hydration begins and lowered when the first synchronization finishes or
///    the app is backgrounded cleanly. Finding it still raised at launch means
///    the previous run died while decoding or reconciling the library, so that
///    data is discarded instead of being replayed into the same crash.
@MainActor
enum LibraryLaunchGuard {
    static let buildStampKey = "heartable.launch.buildStamp"
    static let bootstrapMarkerKey = "heartable.launch.libraryBootstrapInProgress"

    enum Outcome: Equatable, Sendable {
        case kept
        case clearedForNewBuild(previous: String?)
        case clearedAfterAbnormalEnd
    }

    private static let log = Logger(subsystem: "com.zlichtman.heartable", category: "LibraryLaunchGuard")

    /// Call once per launch, before any library cache is read.
    @discardableResult
    static func prepareForLaunch(
        defaults: UserDefaults = .standard,
        currentBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        removeCaches: () -> Void = { AccountSessionStore.removeLibraryCaches(ownerID: nil) }
    ) -> Outcome {
        let previousBuild = defaults.string(forKey: buildStampKey)
        let interrupted = defaults.bool(forKey: bootstrapMarkerKey)
        defaults.set(currentBuild, forKey: buildStampKey)

        let outcome: Outcome
        if previousBuild != currentBuild {
            removeCaches()
            outcome = .clearedForNewBuild(previous: previousBuild)
            log.notice("Library caches cleared for build change \(previousBuild ?? "none", privacy: .public) -> \(currentBuild, privacy: .public)")
        } else if interrupted {
            removeCaches()
            outcome = .clearedAfterAbnormalEnd
            log.error("Previous launch ended during library bootstrap; caches cleared")
        } else {
            outcome = .kept
        }
        defaults.set(false, forKey: bootstrapMarkerKey)
        return outcome
    }

    /// Hydration or the first synchronization is about to touch the caches.
    static func beginBootstrap(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: bootstrapMarkerKey)
    }

    /// The caches were decoded and reconciled, or the app left the foreground
    /// normally; a later termination is no longer evidence of a crash.
    static func finishBootstrap(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: bootstrapMarkerKey)
    }
}
