import UIKit
@preconcurrency import SpotifyiOS

/// Library authorization through Spotify's supported app-to-app session manager.
/// Access-only grants fall back to the existing PKCE flow; they must never replace
/// a durable Web API session with an unrefreshable App Remote token.
@MainActor
final class SpotifyNativeSignIn: NSObject, SPTSessionManagerDelegate {
    static let shared = SpotifyNativeSignIn()

    struct Credentials: Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int

        init?(accessToken: String, refreshToken: String, expiresIn: TimeInterval) {
            guard !accessToken.isEmpty, !refreshToken.isEmpty,
                  expiresIn.isFinite, expiresIn >= 1, expiresIn < Double(Int.max) else { return nil }
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresIn = Int(expiresIn)
        }
    }

    private var manager: SPTSessionManager?
    private var pending: CheckedContinuation<Credentials?, Error>?
    private var timeout: Task<Void, Never>?
    private var requestID = UUID()
    private var ownerID: UUID?

    private let canOpenSpotify: () -> Bool
    private let launch: (SPTSessionManager, String) -> Void
    private let returnGrace: Duration
    private var leftApp = false
    private var receivedCallback = false
    private var returnCheck: Task<Void, Never>?

    init(
        canOpenSpotify: @escaping () -> Bool = {
            UIApplication.shared.canOpenURL(URL(string: "spotify:")!)
        },
        returnGrace: Duration = .seconds(1),
        launch: @escaping (SPTSessionManager, String) -> Void = { manager, scopes in
            manager.initiateSession(withRawScope: scopes, options: .default, campaign: nil)
        }
    ) {
        self.canOpenSpotify = canOpenSpotify
        self.returnGrace = returnGrace
        self.launch = launch
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc func applicationDidEnterBackground() {
        if pending != nil { leftApp = true }
    }

    @objc func applicationDidBecomeActive() {
        guard pending != nil, leftApp, !receivedCallback else { return }
        let request = requestID
        returnCheck?.cancel()
        returnCheck = Task { [weak self, returnGrace] in
            // The callback URL can arrive just after the active notification.
            try? await Task.sleep(for: returnGrace)
            guard !Task.isCancelled, let self, self.requestID == request,
                  self.pending != nil, !self.receivedCallback else { return }
            self.finish(.failure(CancellationError()))
        }
    }

    func signIn(clientID: String, scopes: String, ownerID: UUID) async throws -> Credentials? {
        try Task.checkCancellation()
        // A new explicit Connect tap supersedes any abandoned native session.
        // Its old callback/delegate must never finish the replacement request.
        finish(.failure(CancellationError()))
        guard canOpenSpotify() else { return nil }
        let request = UUID()
        requestID = request
        self.ownerID = ownerID
        let configuration = SPTConfiguration(clientID: clientID,
            redirectURL: URL(string: SpotifyAuth.redirectURI)!)
        // Connecting a library must not start music.
        configuration.playURI = nil
        let manager = SPTSessionManager(configuration: configuration, delegate: self)
        self.manager = manager
        manager.alwaysShowAuthorizationDialog = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled, self?.requestID == request else { return }
                    self?.finish(.failure(ProviderError("Spotify sign-in timed out. Try connecting again.")))
                }
                launch(manager, scopes)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.requestID == request else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func handle(_ url: URL) -> Bool {
        guard pending != nil, url.scheme == "heartable", url.host == "callback",
              let manager else { return false }
        guard ownerID == AccountSessionStore.currentOwnerID else {
            finish(.failure(ProviderError("Your Heartable session changed. Connect Spotify again.")))
            return true
        }
        receivedCallback = true
        let handled = manager.application(UIApplication.shared, open: url, options: [:])
        if !handled { receivedCallback = false }
        return handled
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        let managerID = ObjectIdentifier(manager)
        let credentials = Credentials(accessToken: session.accessToken,
            refreshToken: session.refreshToken, expiresIn: session.expirationDate.timeIntervalSinceNow)
        Task { @MainActor [weak self] in
            guard let self, let active = self.manager, ObjectIdentifier(active) == managerID else { return }
            guard self.ownerID == AccountSessionStore.currentOwnerID else {
                self.finish(.failure(ProviderError("Your Heartable session changed. Connect Spotify again.")))
                return
            }
            self.finish(.success(credentials))
        }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        let managerID = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in
            guard let self, let active = self.manager, ObjectIdentifier(active) == managerID else { return }
            // SDK errors can contain callback URLs. Keep credentials out of feedback.
            self.finish(.failure(ProviderError("Spotify sign-in was cancelled or could not finish. Try connecting again.")))
        }
    }

    private func finish(_ result: Result<Credentials?, Error>) {
        returnCheck?.cancel()
        returnCheck = nil
        leftApp = false
        receivedCallback = false
        timeout?.cancel()
        timeout = nil
        manager?.delegate = nil
        manager = nil
        ownerID = nil
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }
}
