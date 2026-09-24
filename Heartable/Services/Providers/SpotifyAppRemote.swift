import UIKit
import os
@preconcurrency import SpotifyiOS

/// Spotify's supported cold-start path. The SDK briefly opens Spotify, starts
/// the requested URI, and redirects back. Its token stays in memory and never
/// replaces the account-bound Web API credentials.
@MainActor
final class SpotifyAppRemote: NSObject, SPTAppRemoteDelegate {
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
                MainThreadStallMonitor.note("spotify app handoff")
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

    /// Installs Heartable's order through the SDK on the phone player that
    /// `wakeAndPlay` just started: shuffle off, repeat off, an optional seek,
    /// then the following songs enqueued in order. Reuse the connection from
    /// the native handoff without a second Web API playback request.
    func installQueue(following uris: [String], positionMs: Int = 0) async throws {
        guard let remote, remote.isConnected, let player = remote.playerAPI,
              ownerID == AccountSessionStore.currentOwnerID else {
            throw ProviderError("Spotify on this iPhone isn’t connected to Heartable right now.")
        }
        try await call { player.setShuffle(false, callback: $0) }
        try await call { player.setRepeatMode(.off, callback: $0) }
        if positionMs > 0 {
            try await call { player.seek(toPosition: positionMs, callback: $0) }
        }
        for uri in uris {
            try Task.checkCancellation()
            try await call { player.enqueueTrackUri(uri, callback: $0) }
        }
    }

    /// One SDK command. A dropped App Remote connection can leave its callback
    /// unanswered forever; every later start awaits this one, so a bounded
    /// wait keeps a single lost callback from freezing playback until relaunch.
    private func call(timeout: Duration = .seconds(10),
                      _ command: (@escaping SPTAppRemoteCallback) -> Void) async throws {
        let answered = OSAllocatedUnfairLock(initialState: false)
        let claim: @Sendable () -> Bool = {
            answered.withLock { done in
                defer { done = true }
                return !done
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let deadline = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, claim() else { return }
                continuation.resume(throwing: ProviderError("Spotify on this iPhone didn’t answer. Tap the song to try again."))
            }
            command { _, error in
                deadline.cancel()
                guard claim() else { return }
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
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
                async let expected = SpotifyAPI.playbackUser(token: webToken)
                async let actual = SpotifyAPI.playbackUser(token: token)
                let (webUser, appUser) = try await (expected, actual)
                guard requestID == request, ownerID == AccountSessionStore.currentOwnerID else { return }
                guard webUser.id == appUser.id else {
                    throw ProviderError("The Spotify app is signed into a different account. Use the Spotify account connected to Heartable.")
                }
                remote.connectionParameters.accessToken = token
                if UIApplication.shared.applicationState == .active { remote.connect() }
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

    // The SDK delivers these on the thread that created the connection, which is
    // main today. They are nonisolated and hop explicitly anyway: a main-actor
    // @objc delegate called from another queue is exactly the runtime trap that
    // SpotifyNativeSignIn shipped in builds 85–86.
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        let remoteID = ObjectIdentifier(appRemote)
        let connected = UncheckedSendableBox(appRemote)
        Task { @MainActor [weak self] in
            guard let self, let remote, ObjectIdentifier(remote) == remoteID,
                  let uri = requestedURI, pending != nil,
                  ownerID == AccountSessionStore.currentOwnerID else { return }
            let request = requestID
            connected.value.playerAPI?.play(uri) { @Sendable [weak self] _, error in
                Task { @MainActor in
                    guard let self, self.requestID == request else { return }
                    if let error { self.finish(.failure(error)) }
                    else { self.finish(.success(())) }
                }
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let remoteID = ObjectIdentifier(appRemote)
        Task { @MainActor [weak self] in
            guard let self, let remote, ObjectIdentifier(remote) == remoteID, !awaitingCallback else { return }
            finish(.failure(ProviderError("Couldn’t connect to Spotify on this iPhone. Tap the song to retry.")))
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        // An app switch disconnects the socket; foregrounding reconnects it.
    }
}

/// Carries an SDK object across the hop to the main actor. The SDK object is
/// only touched there, on the thread that owns its connection.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
