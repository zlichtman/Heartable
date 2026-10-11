import AuthenticationServices
import UIKit

/// Resolves the foreground window used by Apple and provider authentication
/// sheets. Authentication is only started from visible UI, so reaching this
/// without a connected window scene is a programming error rather than a useful
/// empty-window fallback.
@MainActor
enum PresentationAnchorResolver {
    static func current() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        else {
            preconditionFailure("Authentication requires a connected window scene.")
        }
        return scene.keyWindow ?? ASPresentationAnchor(windowScene: scene)
    }
}
