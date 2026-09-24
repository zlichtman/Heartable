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
/// Exactly one situation discards them: an abnormal end while decoding. Two
/// markers scope that decision to what was actually being decoded.
///
/// - The library marker covers the browse cache (top, liked, playlist catalog).
///   Found raised at launch, every derived cache is discarded.
/// - The playlist-index marker covers the per-playlist content index, by far the
///   largest decode on a playlist-heavy account. Found raised, only that index
///   is discarded: Home still paints from the browse cache, and the next sync
///   re-walks playlists instead of re-pulling the whole library.
///
/// Neither marker covers the provider sync that follows: that can run for
/// minutes, and a user or Xcode killing the app during it is normal, not
/// evidence the caches are bad. Identity, pairings, Keychain items, backups
/// and appearance are never touched by this path.
@MainActor
enum LibraryLaunchGuard {
    static let buildStampKey = "heartable.launch.buildStamp"
    static let bootstrapMarkerKey = "heartable.launch.libraryBootstrapInProgress"
    static let playlistIndexMarkerKey = "heartable.launch.playlistIndexDecodeInProgress"

    enum Outcome: Equatable, Sendable {
        case kept
        case keptAcrossBuildChange(previous: String?)
        case clearedAfterAbnormalEnd
        case clearedPlaylistIndexAfterAbnormalEnd
    }

    private static let log = Logger(subsystem: "com.zlichtman.heartable", category: "LibraryLaunchGuard")

    /// Call once per launch, before any library cache is read.
    @discardableResult
    static func prepareForLaunch(
        defaults: UserDefaults = .standard,
        currentBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        removeCaches: () -> Void = { AccountSessionStore.removeLibraryCaches(ownerID: nil) },
        removePlaylistIndex: () -> Void = { AccountSessionStore.removePlaylistIndexCache(ownerID: nil) }
    ) -> Outcome {
        let previousBuild = defaults.string(forKey: buildStampKey)
        let interrupted = defaults.bool(forKey: bootstrapMarkerKey)
        let playlistIndexInterrupted = defaults.bool(forKey: playlistIndexMarkerKey)
        defaults.set(currentBuild, forKey: buildStampKey)

        let outcome: Outcome
        if interrupted {
            removeCaches()
            outcome = .clearedAfterAbnormalEnd
            log.error("Previous launch ended while decoding the library cache; caches cleared")
        } else if playlistIndexInterrupted {
            removePlaylistIndex()
            outcome = .clearedPlaylistIndexAfterAbnormalEnd
            log.error("Previous launch ended while decoding the playlist index; index cleared, library kept")
        } else if previousBuild != currentBuild {
            outcome = .keptAcrossBuildChange(previous: previousBuild)
            log.notice("Build change \(previousBuild ?? "none", privacy: .public) -> \(currentBuild, privacy: .public); library caches kept")
        } else {
            outcome = .kept
        }
        defaults.set(false, forKey: bootstrapMarkerKey)
        defaults.set(false, forKey: playlistIndexMarkerKey)
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

    /// The playlist-content index is about to be decoded.
    static func beginPlaylistIndexDecode(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: playlistIndexMarkerKey)
    }

    static func finishPlaylistIndexDecode(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: playlistIndexMarkerKey)
    }
}
