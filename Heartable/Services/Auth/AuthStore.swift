import Foundation
import Supabase

/// Supabase owns the Heartable account through Apple or email/password sign-in.
/// Music services are paired separately and are never authentication methods.
/// `RootView` gates on `session` once the restored auth state has loaded.
@MainActor
@Observable
final class AuthStore {
    private(set) var session: Session?
    private(set) var loaded = false

    let client: SupabaseClient
    var isConfigured: Bool { AppConfig.isConfigured }
    var userID: UUID? { session?.user.id }

    private var observeTask: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
        // The stream emits `.initialSession` immediately, so `loaded` flips on
        // first tick (after the client restores any persisted session).
        observeTask = Task { [weak self, client] in
            for await state in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                // Activate only this Heartable account's provider namespace before
                // publishing the session to the UI.
                await AccountSessionStore.prepare(for: state.session?.user.id)
                guard !Task.isCancelled, let self else { return }
                self.session = state.session
                self.loaded = true
            }
        }
    }

    func signInWithPassword(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: Self.normalizedEmail(email), password: password)
    }

    /// Returns true when the account needs email confirmation (no session yet).
    func signUp(email: String, password: String) async throws -> Bool {
        let res = try await client.auth.signUp(
            email: Self.normalizedEmail(email),
            password: password
        )
        return res.session == nil
    }

    func signInWithApple() async throws {
        let result = try await AppleSignIn.run()
        _ = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: result.idToken, nonce: result.nonce)
        )
    }

    func resetPassword(email: String) async throws {
        // Use the Supabase project's configured recovery redirect. A custom
        // app-scheme redirect would be a dead end until Heartable has an
        // authenticated "choose a new password" callback flow.
        try await client.auth.resetPasswordForEmail(Self.normalizedEmail(email))
    }

    nonisolated static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func signOut() async throws {
        // Signing out deactivates the account namespace; it does not disconnect
        // music services. They are restored when this Heartable account returns.
        try await client.auth.signOut()
    }

    /// Permanently delete the account: wipe all server data + the auth user (via
    /// the `delete-account` edge function), then forget every local trace of the
    /// account on this device, then drop the session. After this the app is back
    /// to a fresh-install state with nothing connected.
    func deleteAccount() async throws {
        let deletingUserID = userID
        try await BackendAPI.shared.deleteAccount()
        await ArtworkImageCache.shared.clear()
        await Self.wipeLocalState(ownerID: deletingUserID)
        try? await client.auth.signOut()
    }

    /// Permanently erase only the deleted Heartable account's local provider vault
    /// and caches. Device appearance and other accounts remain untouched.
    static func wipeLocalState(ownerID: UUID?) async {
        await AccountSessionStore.clear(ownerID: ownerID)
        guard let ownerID else { return }
        let defaults = UserDefaults.standard
        let onboardingKey = "heartable.onboarded.userIDs"
        var onboarded = Set(
            (defaults.string(forKey: onboardingKey) ?? "")
                .split(separator: ",")
                .map(String.init)
        )
        onboarded.remove(ownerID.uuidString)
        defaults.set(onboarded.sorted().joined(separator: ","), forKey: onboardingKey)
    }
}
