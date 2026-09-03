import UIKit

/// Only a visible playlist opts into landscape. The rest of the app keeps its
/// portrait contract, including after switching tabs or signing out.
@MainActor
enum PlaylistRotation {
    private static var visiblePlaylists: Set<UUID> = []

    static var supportedOrientations: UIInterfaceOrientationMask {
        visiblePlaylists.isEmpty ? .portrait : .allButUpsideDown
    }

    static func setVisible(_ visible: Bool, id: UUID) {
        if visible { visiblePlaylists.insert(id) }
        else { visiblePlaylists.remove(id) }

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            guard scene.activationState == .foregroundActive else { continue }
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedOrientations))
        }
    }
}
