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
/// 2. **An abnormal end while decoding.** A marker is raised just before the
///    cached library is decoded and lowered the moment that decode has
///    published. Finding it still raised at launch means the previous run died
///    inside the decode itself, so that data is discarded instead of being
///    replayed into the same crash. The marker deliberately does not cover the
///    provider sync that follows: that can run for minutes, and a user or Xcode
///    killing the app during it is normal, not evidence the caches are bad.
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

    /// The cached library is about to be decoded.
    static func beginBootstrap(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: bootstrapMarkerKey)
    }

    /// The caches decoded and published; a later termination is not a crash here.
    static func finishBootstrap(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: bootstrapMarkerKey)
    }
}
