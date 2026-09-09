import UIKit
@preconcurrency import SpotifyiOS

/// Spotify's supported cold-start path. The SDK briefly opens Spotify, starts
/// the requested URI, and redirects back. Its token stays in memory and never
/// replaces the account-bound Web API credentials.
@MainActor
final class SpotifyAppRemote: NSObject, @preconcurrency SPTAppRemoteDelegate {
    static let shared = SpotifyAppRemote()
    private var remote: SPTAppRemote?
    private var pending: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var requestedURI: String?
    private var ownerID: UUID?
    private var requestID = UUID()
    private var awaitingCallback = false

    var isConnected: Bool { remote?.isConnected == true }

    func wakeAndPlay(_ track: UnifiedTrack) async throws {
        reset()
        guard UIApplication.shared.applicationState == .active else {
            throw ProviderError("Open Heartable to start Spotify on this iPhone.")
        }
        guard let clientID = AppConfig.spotifyClientID,
              let owner = AccountSessionStore.currentOwnerID else {
            throw ProviderError("Connect Spotify in Music Services first.")
        }
        guard UIApplication.shared.canOpenURL(URL(string: "spotify:")!) else {
            throw ProviderError("Install Spotify on this iPhone to start its player, or choose a Spotify Connect device.")
        }
        let configuration = SPTConfiguration(clientID: clientID,
                                              redirectURL: URL(string: SpotifyAuth.redirectURI)!)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        self.remote = remote
        remote.delegate = self
        ownerID = owner
        requestedURI = track.uri
        awaitingCallback = true
        let request = requestID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(90))
                    guard !Task.isCancelled, self?.requestID == request else { return }
                    self?.finish(.failure(ProviderError("Spotify didn’t finish opening. Tap the song to try again.")))
                }
                remote.authorizeAndPlayURI(track.uri, asRadio: false,
                    additionalScopes: ["user-read-private"]) { [weak self] installed in
                    Task { @MainActor in
                        guard self?.requestID == request, !installed else { return }
                        self?.finish(.failure(ProviderError("Spotify couldn’t open on this iPhone.")))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.requestID == request else { return }
                self?.reset()
            }
        }
    }

    func handle(_ url: URL) {
        guard awaitingCallback, pending != nil,
              url.scheme == "heartable", url.host == "callback",
              ownerID == AccountSessionStore.currentOwnerID,
              let remote, let parameters = remote.authorizationParameters(from: url) else { return }
        awaitingCallback = false
        guard let token = parameters[SPTAppRemoteAccessTokenKey] else {
            finish(.failure(ProviderError("Spotify playback authorization was cancelled or declined.")))
            return
        }
        let request = requestID
        Task {
            do {
                guard let webToken = await SpotifyAuth.getValidAccessToken() else {
                    throw ProviderError("Reconnect Spotify in Music Services.")
                }
                async let expected = SpotifyAPI.me(token: webToken)
                async let actual = SpotifyAPI.me(token: token)
                let (webUser, appUser) = try await (expected, actual)
                guard requestID == request, ownerID == AccountSessionStore.currentOwnerID else { return }
                guard webUser.id == appUser.id else {
                    throw ProviderError("The Spotify app is signed into a different account. Use the Spotify account connected to Heartable.")
                }
                remote.connectionParameters.accessToken = token
                remote.connect()
            } catch {
                guard requestID == request else { return }
                finish(.failure(error))
            }
        }
    }

    func setActive(_ active: Bool) {
        guard ownerID == AccountSessionStore.currentOwnerID else { reset(); return }
        if active, !awaitingCallback, remote?.connectionParameters.accessToken != nil {
            remote?.connect()
        } else if !active {
            remote?.disconnect()
        }
    }

    func reset() {
        requestID = UUID()
        finish(.failure(CancellationError()))
        remote?.delegate = nil
        remote?.disconnect()
        remote = nil
        ownerID = nil
    }

    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel()
        timeout = nil
        awaitingCallback = false
        requestedURI = nil
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        guard appRemote === remote, let uri = requestedURI, pending != nil,
              ownerID == AccountSessionStore.currentOwnerID else { return }
        let request = requestID
        appRemote.playerAPI?.play(uri) { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.requestID == request else { return }
                if let error { self.finish(.failure(error)) }
                else { self.finish(.success(())) }
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        guard appRemote === remote, !awaitingCallback else { return }
        finish(.failure(ProviderError("Couldn’t connect to Spotify on this iPhone. Tap the song to retry.")))
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        // An app switch disconnects the socket; foregrounding reconnects it.
    }
}
