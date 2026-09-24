import UIKit
import Observation

/// Only a visible playlist opts into landscape. The rest of the app keeps its
/// portrait contract, including after switching tabs or signing out.
@MainActor
enum PlaylistRotation {
    private static let state = PlaylistVisibility()

    /// Observed by the app shell. Assigned only on a real visible/hidden
    /// transition: a repeated appear/disappear callback for the same playlist
    /// must not re-render the TabView or its native accessory.
    static var hasVisiblePlaylist: Bool { state.visible }

    static var supportedOrientations: UIInterfaceOrientationMask {
        hasVisiblePlaylist ? .allButUpsideDown : .portrait
    }

    static func setVisible(_ visible: Bool, id: UUID) {
        let wasVisible = state.visible
        var ids = state.ids
        if visible { ids.insert(id) } else { ids.remove(id) }
        state.ids = ids
        let isVisible = !ids.isEmpty
        guard isVisible != wasVisible else { return }
        state.visible = isVisible
        MainThreadStallMonitor.note(hasVisiblePlaylist ? "orientation: landscape allowed" : "orientation: portrait only")

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            guard scene.activationState == .foregroundActive else { continue }
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedOrientations))
        }
    }
}

@MainActor @Observable
private final class PlaylistVisibility {
    /// Bookkeeping only; nothing renders from the individual identifiers.
    @ObservationIgnored var ids: Set<UUID> = []
    var visible = false
}

/// Player existence must never change the chrome contract within a playlist.
enum PlaylistChromePolicy {
    static func reservesPlayer(playlistVisible: Bool, hasNowPlaying: Bool) -> Bool {
        playlistVisible || hasNowPlaying
    }
    /// iOS 26 re-hosts the bottom accessory each time the bar minimizes or
    /// expands (inline ↔ expanded placement), rebuilding the mini-player and
    /// its native route picker. Aaron's iOS 26.6.2 watchdogs sat in exactly
    /// that UIKit-layout → SwiftUI-update path, so the bar stays expanded there.
    static func allowsMinimizing(playlistVisible: Bool, hasNowPlaying: Bool,
                                 systemSupportsStableAccessory: Bool = true) -> Bool {
        systemSupportsStableAccessory && !playlistVisible && hasNowPlaying
    }

    static var systemSupportsStableAccessory: Bool {
        if #available(iOS 27, *) { return true }
        return false
    }
}
