import Foundation
import os

/// Keeps a launch from replaying a library cache that crashed the previous run.
///
/// The library is cache-first: the derived caches are what make an update or a
/// relaunch show the user's playlists immediately, and re-deriving them means
/// pulling the whole library from the providers again (hundreds of Spotify
/// requests for a large liked library, which is exactly what trips Spotify's
/// rate limiter). They are therefore never discarded on a build change.
///
/// Exactly one situation discards them: an abnormal end while decoding. A
/// marker is raised just before the cached library is decoded and lowered the
/// moment that decode has published. Finding it still raised at launch means
/// the previous run died inside the decode itself, so that data is discarded
/// instead of being replayed into the same crash. The marker deliberately does
/// not cover the provider sync that follows: that can run for minutes, and a
/// user or Xcode killing the app during it is normal, not evidence the caches
/// are bad. Identity, pairings, Keychain items, backups and appearance are
/// never touched by this path.
@MainActor
enum LibraryLaunchGuard {
    static let buildStampKey = "heartable.launch.buildStamp"
    static let bootstrapMarkerKey = "heartable.launch.libraryBootstrapInProgress"

    enum Outcome: Equatable, Sendable {
        case kept
        case keptAcrossBuildChange(previous: String?)
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
        if interrupted {
            removeCaches()
            outcome = .clearedAfterAbnormalEnd
            log.error("Previous launch ended while decoding the library cache; caches cleared")
        } else if previousBuild != currentBuild {
            outcome = .keptAcrossBuildChange(previous: previousBuild)
            log.notice("Build change \(previousBuild ?? "none", privacy: .public) -> \(currentBuild, privacy: .public); library caches kept")
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
