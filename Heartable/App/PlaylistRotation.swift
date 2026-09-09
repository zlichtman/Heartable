import UIKit
import Observation

/// Only a visible playlist opts into landscape. The rest of the app keeps its
/// portrait contract, including after switching tabs or signing out.
@MainActor
enum PlaylistRotation {
    private static let state = PlaylistVisibility()

    static var hasVisiblePlaylist: Bool { !state.ids.isEmpty }

    static var supportedOrientations: UIInterfaceOrientationMask {
        hasVisiblePlaylist ? .allButUpsideDown : .portrait
    }

    static func setVisible(_ visible: Bool, id: UUID) {
        let wasVisible = hasVisiblePlaylist
        if visible { state.ids.insert(id) }
        else { state.ids.remove(id) }
        guard hasVisiblePlaylist != wasVisible else { return }

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
    var ids: Set<UUID> = []
}

/// Player existence must never change the chrome contract within a playlist.
enum PlaylistChromePolicy {
    static func reservesPlayer(playlistVisible: Bool, hasNowPlaying: Bool) -> Bool {
        playlistVisible || hasNowPlaying
    }
    static func allowsMinimizing(playlistVisible: Bool, hasNowPlaying: Bool) -> Bool {
        !playlistVisible && hasNowPlaying
    }
}
