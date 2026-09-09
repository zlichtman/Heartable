import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Spotify Authorization Code + PKCE OAuth, ported from the RN `src/spotify/auth.ts`.
///
/// The interactive sign-in runs through `ASWebAuthenticationSession` (the native
/// equivalent of expo-web-browser's `openAuthSessionAsync`), captures the
/// `heartable://callback` redirect, exchanges the code for tokens at Spotify's token
/// endpoint, and stores access/refresh/expiry in the Keychain. `getValidAccessToken`
/// returns a cached token, refreshes it when it's within 30s of expiry, or returns
/// nil when signed out. There's no client secret — PKCE is the proof.
enum SpotifyAuth {
    /// Custom-scheme redirect — must match the URI registered in the Spotify
    /// dashboard verbatim (heartable://callback).
    static let redirectURI = "heartable://callback"
    private static let callbackScheme = "heartable"

    private static let keyAccess = "heartable_spotify_access"
    private static let keyRefresh = "heartable_spotify_refresh"
    private static let keyRefreshPrev = "heartable_spotify_refresh_prev"
    private static let keyExpiry = "heartable_spotify_expiry"

    /// Same scope set as the RN app — keep in sync with the Spotify dashboard.
    private static let scopes = [
        "user-read-email",
        "user-read-private",
        "user-top-read",
        "user-library-read",
        "user-library-modify",
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-public",
        "playlist-modify-private",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
    ].joined(separator: " ")

    private static let authorizeURL = "https://accounts.spotify.com/authorize"
    private static let tokenURL = "https://accounts.spotify.com/api/token"

    // MARK: - Public API

    /// Full interactive sign-in. Presents the Spotify consent screen, exchanges the
    /// returned code for tokens, and persists the session. Throws a user-facing
    /// `ProviderError` on cancel/failure.
    static func signIn() async throws {
        guard let clientID = AppConfig.spotifyClientID else {
            throw ProviderError("Spotify is not configured.")
        }
        guard let ownerID = AccountSessionStore.currentOwnerID else {
            throw ProviderError("Sign in to Heartable before connecting Spotify.")
        }
        let vaultGeneration = await RefreshGate.shared.generation(for: ownerID)

        let verifier = randomVerifier()
        let challenge = challenge(for: verifier)

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            // Force the consent screen so reconnecting re-grants the FULL scope set.
            // Without this, Spotify silently reuses an older grant, so a token minted
            // before playlist-read-private was requested keeps 403-ing on
            // /playlists/{id}/tracks (capture saved playlists but zero tracks).
            URLQueryItem(name: "show_dialog", value: "true"),
        ]
        guard let authURL = components.url else {
            throw ProviderError("Couldn't build the Spotify sign-in URL.")
        }

        let callback = try await WebAuth.start(url: authURL, scheme: callbackScheme)

        guard let returned = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw ProviderError("Spotify returned an unreadable response.")
        }
        let items = returned.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw ProviderError("Spotify: \(err)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw ProviderError("No authorization code returned.")
        }
        guard AccountSessionStore.currentOwnerID == ownerID else {
            throw ProviderError("Your Heartable session changed. Connect Spotify again.")
        }

        try await exchangeCode(
            code,
            clientID: clientID,
            verifier: verifier,
            ownerID: ownerID,
            vaultGeneration: vaultGeneration
        )
    }

    /// Returns a valid access token, refreshing if it's within 30s of expiring, or
    /// nil if signed out. Never throws — callers treat nil as not-connected.
    static func getValidAccessToken() async -> String? {
        guard let clientID = AppConfig.spotifyClientID,
              let ownerID = AccountSessionStore.currentOwnerID else { return nil }

        // Use the cached access token while it's comfortably unexpired.
        if let token = AccountSessionStore.keychainValue(forKey: keyAccess, ownerID: ownerID),
           let expiryString = AccountSessionStore.keychainValue(forKey: keyExpiry, ownerID: ownerID),
           let expiry = Double(expiryString) {
            // expiry is epoch milliseconds (matching the RN `Date.now()` model).
            let nowMs = Date().timeIntervalSince1970 * 1000
            if nowMs < expiry - 30_000 { return token }
        }

        // Access token missing or near expiry — refresh as long as a session exists.
        // (Returns nil on a transient failure but keeps the session for next time.)
        guard AccountSessionStore.keychainValue(
            forKey: keyRefresh,
            ownerID: ownerID
        ) != nil else { return nil }
        // Single-flight: many callers (player poll + every Library provider read)
        // hit this at once when the token expires. Without coordination they'd each
        // POST the SAME refresh token; Spotify rotates it on the first success and
        // rejects the rest with invalid_grant — which used to wipe the session and
        // disconnect Spotify. The gate ensures exactly one refresh runs and everyone
        // awaits its result.
        let refreshed = await RefreshGate.shared.token(
            clientID: clientID,
            ownerID: ownerID
        )
        guard AccountSessionStore.currentOwnerID == ownerID else { return nil }
        return refreshed
    }

    /// Whether a Spotify session exists — i.e. we hold a refresh token. This is the
    /// source of truth for "connected": it stays true across transient access-token
    /// refresh failures (network blips, 5xx, 429) and only goes false when the
    /// refresh token is genuinely revoked (400/401) and `clearSession()` runs.
    /// Connection status must NOT depend on a live token fetch succeeding.
    static var isSignedIn: Bool {
        AccountSessionStore.keychainValue(forKey: keyRefresh) != nil
    }

    /// Wipes only one Heartable account's Spotify pairing.
    static func clearSession(
        ownerID: UUID? = AccountSessionStore.currentOwnerID
    ) async {
        guard let ownerID else { return }
        await RefreshGate.shared.invalidate(ownerID)
        for key in [keyAccess, keyRefresh, keyRefreshPrev, keyExpiry] {
            AccountSessionStore.deleteKeychainValue(forKey: key, ownerID: ownerID)
        }
    }

    // MARK: - Token exchange / refresh

    private static func exchangeCode(
        _ code: String,
        clientID: String,
        verifier: String,
        ownerID: UUID,
        vaultGeneration: Int
    ) async throws {
        let body = formEncode([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        let token = try await postToken(body)
        guard AccountSessionStore.currentOwnerID == ownerID,
              await RefreshGate.shared.isCurrent(
                  vaultGeneration,
                  for: ownerID
              ) else {
            throw ProviderError("Your Heartable session changed. Connect Spotify again.")
        }
        await saveSession(
            token,
            fallbackRefresh: nil,
            ownerID: ownerID,
            vaultGeneration: vaultGeneration
        )
    }

    /// Serializes refreshes so concurrent callers share one network round-trip
    /// instead of racing the same (rotated-on-use) refresh token. The first caller
    /// runs the refresh; everyone else awaits the same task and gets its result.
    private actor RefreshGate {
        static let shared = RefreshGate()
        private var inflight: [UUID: Task<String?, Never>] = [:]
        private var generations: [UUID: Int] = [:]

        func generation(for ownerID: UUID) -> Int {
            generations[ownerID, default: 0]
        }

        func isCurrent(_ generation: Int, for ownerID: UUID) -> Bool {
            generations[ownerID, default: 0] == generation
        }

        func invalidate(_ ownerID: UUID) {
            generations[ownerID, default: 0] &+= 1
            inflight[ownerID]?.cancel()
            inflight[ownerID] = nil
        }

        func token(clientID: String, ownerID: UUID) async -> String? {
            if let existing = inflight[ownerID] { return await existing.value }
            let generation = generations[ownerID, default: 0]
            let task = Task {
                await SpotifyAuth.performRefresh(
                    clientID: clientID,
                    ownerID: ownerID,
                    vaultGeneration: generation
                )
            }
            inflight[ownerID] = task
            let result = await task.value
            if generations[ownerID, default: 0] == generation {
                inflight[ownerID] = nil
            }
            return result
        }
    }

    private enum RefreshOutcome { case ok(String), rejected, transient }

    /// Refreshes using the stored refresh token, with a fallback to the previous one.
    ///
    /// Spotify rotates the refresh token on use and invalidates the old one. If the
    /// app is killed in the window between Spotify rotating and us persisting the new
    /// token, the stored token can be stale on the next launch — which is exactly the
    /// "Spotify drops on every app exit" symptom. We keep the prior refresh token and
    /// retry with it once before giving up. The session is wiped ONLY when both the
    /// current and previous tokens are explicitly rejected (`invalid_grant`) and the
    /// stored token hasn't been rotated out from under us meanwhile. Transient errors
    /// (network, 5xx, 429, non-grant 400s) keep the session for the next attempt.
    fileprivate static func performRefresh(
        clientID: String,
        ownerID: UUID,
        vaultGeneration: Int
    ) async -> String? {
        guard let refresh = AccountSessionStore.keychainValue(
            forKey: keyRefresh,
            ownerID: ownerID
        ) else { return nil }

        switch await attempt(
            refresh,
            clientID: clientID,
            ownerID: ownerID,
            vaultGeneration: vaultGeneration
        ) {
        case .ok(let token): return token
        case .transient: return nil          // keep the session, retry later
        case .rejected: break                // current token dead — try the previous one
        }

        if let prev = AccountSessionStore.keychainValue(
            forKey: keyRefreshPrev,
            ownerID: ownerID
        ), prev != refresh,
           case .ok(let token) = await attempt(
               prev,
               clientID: clientID,
               ownerID: ownerID,
               vaultGeneration: vaultGeneration
           ) {
            return token                      // recovered via the prior token
        }

        // Genuinely unrecoverable — but only clear if no concurrent refresh already
        // rotated the stored token (in which case this rejection is stale).
        if AccountSessionStore.keychainValue(
            forKey: keyRefresh,
            ownerID: ownerID
        ) == refresh {
            await clearSession(ownerID: ownerID)
        }
        return nil
    }

    private static func attempt(
        _ refresh: String,
        clientID: String,
        ownerID: UUID,
        vaultGeneration: Int
    ) async -> RefreshOutcome {
        let body = formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ])
        do {
            let token = try await postToken(body)
            await saveSession(
                token,
                fallbackRefresh: refresh,
                ownerID: ownerID,
                vaultGeneration: vaultGeneration
            )
            guard await RefreshGate.shared.isCurrent(
                vaultGeneration,
                for: ownerID
            ) else { return .transient }
            return .ok(token.accessToken)
        } catch let e as TokenError where e.isInvalidGrant {
            return .rejected
        } catch {
            return .transient
        }
    }

    private static func postToken(_ body: String) async throws -> TokenResponse {
        guard let url = URL(string: tokenURL) else {
            throw ProviderError("Invalid Spotify token URL.")
        }
        let (data, resp) = try await HTTPClient.send(
            url,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(body.utf8)
        )
        guard (200..<300).contains(resp.statusCode) else {
            let code = (try? JSONDecoder().decode(TokenErrorBody.self, from: data))?.error
            throw TokenError(status: resp.statusCode, code: code)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    /// Token-endpoint failure. Only a parsed `invalid_grant` means the refresh token
    /// is genuinely revoked (sign-in required); every other status/error is treated
    /// as transient so it never drops the session. The over-broad "any 400/401 =
    /// revoked" rule used to cause spurious disconnects under concurrent refreshes.
    private struct TokenError: LocalizedError {
        let status: Int
        let code: String?
        var isInvalidGrant: Bool { code == "invalid_grant" }
        var errorDescription: String? { "Spotify token request failed (\(status))." }
    }

    /// Spotify's OAuth error payload, e.g. `{"error":"invalid_grant", ...}`.
    private struct TokenErrorBody: Decodable { let error: String? }

    /// Persists tokens + an absolute expiry (epoch ms). Keeps the prior refresh
    /// token when Spotify doesn't return a fresh one.
    private static func saveSession(
        _ token: TokenResponse,
        fallbackRefresh: String?,
        ownerID: UUID,
        vaultGeneration: Int
    ) async {
        guard await RefreshGate.shared.isCurrent(
            vaultGeneration,
            for: ownerID
        ) else { return }
        AccountSessionStore.setKeychainValue(
            token.accessToken,
            forKey: keyAccess,
            ownerID: ownerID
        )
        let expiryMs = Date().timeIntervalSince1970 * 1000 + Double(token.expiresIn) * 1000
        AccountSessionStore.setKeychainValue(
            String(expiryMs),
            forKey: keyExpiry,
            ownerID: ownerID
        )
        if let newRefresh = token.refreshToken {
            // Rotation: keep the token being replaced as the fallback, so an
            // interrupted save on a prior launch is still recoverable.
            if let current = AccountSessionStore.keychainValue(
                forKey: keyRefresh,
                ownerID: ownerID
            ), current != newRefresh {
                AccountSessionStore.setKeychainValue(
                    current,
                    forKey: keyRefreshPrev,
                    ownerID: ownerID
                )
            }
            AccountSessionStore.setKeychainValue(
                newRefresh,
                forKey: keyRefresh,
                ownerID: ownerID
            )
        } else if let fallbackRefresh,
                  AccountSessionStore.keychainValue(
                      forKey: keyRefresh,
                      ownerID: ownerID
                  ) == nil {
            AccountSessionStore.setKeychainValue(
                fallbackRefresh,
                forKey: keyRefresh,
                ownerID: ownerID
            )
        }
        // If explicit disconnect raced the synchronous Keychain writes, remove
        // anything this stale request managed to recreate.
        guard await RefreshGate.shared.isCurrent(
            vaultGeneration,
            for: ownerID
        ) else {
            for key in [keyAccess, keyRefresh, keyRefreshPrev, keyExpiry] {
                AccountSessionStore.deleteKeychainValue(
                    forKey: key,
                    ownerID: ownerID
                )
            }
            return
        }
    }

    // MARK: - PKCE

    /// 64-char base64url verifier from 48 random bytes (>= the 43-char minimum and
    /// comfortably past the RN app's 32-byte verifier).
    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    /// S256 challenge: base64url( SHA256( ASCII(verifier) ) ).
    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    // MARK: - Decodable

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}

// MARK: - ASWebAuthenticationSession bridge

/// Bridges `ASWebAuthenticationSession` to async/await with a presentation context
/// provider pinned to the foreground key window. Mirrors `AppleSignIn`'s coordinator
/// pattern: the helper retains itself until the callback fires.
@MainActor
private final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var retain: WebAuth?

    static func start(url: URL, scheme: String) async throws -> URL {
        let helper = WebAuth()
        return try await helper.run(url: url, scheme: scheme)
    }

    private func run(url: URL, scheme: String) async throws -> URL {
        retain = self
        defer { retain = nil }
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: ProviderError("Spotify connection was cancelled."))
                    } else {
                        cont.resume(throwing: ProviderError(error.localizedDescription))
                    }
                } else {
                    cont.resume(throwing: ProviderError("Spotify sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        PresentationAnchorResolver.current()
    }
}
