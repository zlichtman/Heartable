import AuthenticationServices
import CryptoKit
import UIKit

/// Runs the native Sign in with Apple flow and returns the identity token plus
/// the raw nonce (Supabase verifies the nonce hash in the token). Bridges the
/// delegate-based `ASAuthorizationController` to async/await.
enum AppleSignIn {
    struct Result: Sendable {
        let idToken: String
        let nonce: String
    }

    enum Failure: LocalizedError {
        case cancelled, noToken
        var errorDescription: String? {
            switch self {
            case .cancelled: "Sign in with Apple was cancelled."
            case .noToken: "Apple didn't return an identity token."
            }
        }
    }

    @MainActor
    static func run() async throws -> Result {
        let rawNonce = randomNonceString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)

        let coordinator = Coordinator(rawNonce: rawNonce)
        return try await coordinator.perform(request)
    }

    // MARK: - Coordinator

    @MainActor
    private final class Coordinator: NSObject,
        ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding
    {
        private let rawNonce: String
        private var continuation: CheckedContinuation<Result, Error>?
        private var retain: Coordinator?

        init(rawNonce: String) { self.rawNonce = rawNonce }

        func perform(_ request: ASAuthorizationAppleIDRequest) async throws -> Result {
            retain = self // keep alive until the delegate callback fires
            return try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            defer { retain = nil }
            guard
                let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                finish(.failure(Failure.noToken))
                return
            }
            finish(.success(Result(idToken: token, nonce: rawNonce)))
        }

        /// Resume exactly once: a second delegate callback would otherwise trap
        /// on a checked continuation.
        private func finish(_ outcome: Swift.Result<Result, Error>) {
            let pending = continuation
            continuation = nil
            pending?.resume(with: outcome)
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            defer { retain = nil }
            finish(.failure(Failure.cancelled))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            PresentationAnchorResolver.current()
        }
    }

    // MARK: - Nonce

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
