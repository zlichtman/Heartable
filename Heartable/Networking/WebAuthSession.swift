import AuthenticationServices
import Foundation
import os

/// Bridges `ASWebAuthenticationSession` to async/await with a presentation anchor
/// pinned to the foreground key window. The helper retains itself until the
/// callback fires; user-facing errors name the service being connected.
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let serviceName: String
    private var session: ASWebAuthenticationSession?
    private var retain: WebAuthSession?

    private init(serviceName: String) {
        self.serviceName = serviceName
    }

    static func start(url: URL, scheme: String, serviceName: String) async throws -> URL {
        let helper = WebAuthSession(serviceName: serviceName)
        return try await helper.run(url: url, scheme: scheme)
    }

    private func run(url: URL, scheme: String) async throws -> URL {
        retain = self
        defer { retain = nil }
        let serviceName = serviceName
        return try await withCheckedThrowingContinuation { cont in
            // `start()` can report a failure through the handler *and* return
            // false, so both paths go through one resume-once gate.
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let resume: @Sendable (Result<URL, Error>) -> Void = { result in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { cont.resume(with: result) }
            }
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { @Sendable callbackURL, error in
                if let callbackURL {
                    resume(.success(callbackURL))
                } else if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        resume(.failure(ProviderError("\(serviceName) connection was cancelled.")))
                    } else {
                        resume(.failure(ProviderError(error.localizedDescription)))
                    }
                } else {
                    resume(.failure(ProviderError("\(serviceName) sign-in failed.")))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            // When the session cannot be shown its completion handler never
            // runs; answer here so Connect does not spin forever.
            if !session.start() {
                resume(.failure(ProviderError("\(serviceName) sign-in couldn’t open. Try connecting again.")))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PresentationAnchorResolver.current()
    }
}
