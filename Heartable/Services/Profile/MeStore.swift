import Foundation
import Observation

/// The signed-in user's own profile, shared app-wide so a change (avatar, name,
/// handle) propagates everywhere that shows "me" instead of each screen loading
/// its own copy. Injected into the environment; EditProfile mutates it, the
/// Profile header reads it.
@MainActor
@Observable
final class MeStore {
    private(set) var profile: ProfileDTO?
    private(set) var featuredPlaylists: [UnifiedPlaylist] = []
    private(set) var profileModules = ProfileModulePreferenceDTO.defaults
    private(set) var hasLoadedFeaturedPlaylists = false
    private(set) var hasResolvedAccount = false

    private var ownerID: UUID?
    private var profileLoaded = false
    private var profileMutationRevision = 0
    private var curationMutationRevision = 0

    var displayName: String {
        let n = profile?.displayName?.trimmingCharacters(in: .whitespaces)
        return (n?.isEmpty == false ? n! : "Heartable user")
    }
    var handle: String? { profile?.handle }
    var avatarURL: URL? {
        guard let s = profile?.avatarUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }
    var avatarUrlString: String? { profile?.avatarUrl }
    var hasCompletedOnboarding: Bool {
        !(profile?.onboardingCompletedAt?.isEmpty ?? true)
    }

    /// Switch the shared identity state to an account immediately. A cached
    /// public profile is applied synchronously so the first authenticated frame
    /// never falls back to another account or the generic placeholder while the
    /// authoritative Supabase refresh is in flight.
    func activate(userID: UUID?) {
        guard let userID else {
            reset()
            return
        }
        prepare(for: userID)
    }

    func load(userID: UUID?, force: Bool = false) async {
        guard let userID else { return }
        prepare(for: userID)
        guard force || !profileLoaded else { return }

        let revision = profileMutationRevision
        do {
            let fetched = try await BackendAPI.shared.getMyProfile(userID: userID)
            guard ownerID == userID, revision == profileMutationRevision else { return }
            profile = fetched ?? ProfileDTO(userId: userID)
            profileLoaded = true
            hasResolvedAccount = true
            persistProfile()
        } catch {
            guard ownerID == userID else { return }
            if profile == nil {
                profile = ProfileDTO(userId: userID)
            }
            // Resolve the gate even when offline. A local completion marker still
            // admits returning users; unknown accounts can finish onboarding.
            hasResolvedAccount = true
        }
    }

    /// Load the public playlist curation once per account. Callers that need an
    /// explicit retry can pass `force`; normal profile navigation uses the shared
    /// in-memory value and avoids a CDN read plus a full library reload on return.
    @discardableResult
    func loadFeaturedPlaylists(userID: UUID?, force: Bool = false) async throws
        -> [UnifiedPlaylist] {
        guard let userID else { throw BackendError.notSignedIn }
        prepare(for: userID)
        if hasLoadedFeaturedPlaylists, !force {
            return featuredPlaylists
        }

        let revision = curationMutationRevision
        let document = try await BackendAPI.shared.fetchProfileCuration(userID: userID)
        guard ownerID == userID, revision == curationMutationRevision else {
            return featuredPlaylists
        }
        featuredPlaylists = Self.normalizedFeaturedPlaylists(
            document?.playlists.map(\.unified) ?? []
        )
        profileModules = ProfileCurationDTO.normalizedModules(
            document?.modules ?? ProfileModulePreferenceDTO.defaults
        )
        hasLoadedFeaturedPlaylists = true
        return featuredPlaylists
    }

    /// Apply changes locally for an instant, app-wide update (the backend write
    /// is persisted separately by the caller).
    func setAvatar(_ url: String, userID: UUID?) {
        guard let userID else { return }
        prepare(for: userID)
        if profile == nil { profile = ProfileDTO(userId: userID) }
        profile?.avatarUrl = url
        profileLoaded = true
        profileMutationRevision += 1
        persistProfile()
    }

    func setNameHandle(displayName: String?, handle: String?, userID: UUID?) {
        guard let userID else { return }
        prepare(for: userID)
        if profile == nil { profile = ProfileDTO(userId: userID) }
        profile?.displayName = displayName
        profile?.handle = handle
        profileLoaded = true
        profileMutationRevision += 1
        persistProfile()
    }

    func markOnboardingCompleted(userID: UUID?) {
        guard let userID else { return }
        prepare(for: userID)
        if profile == nil { profile = ProfileDTO(userId: userID) }
        profile?.onboardingCompletedAt = ISO8601DateFormatter().string(from: Date())
        profileLoaded = true
        hasResolvedAccount = true
        profileMutationRevision += 1
        persistProfile()
    }

    /// Apply the exact ordered selection that was accepted by the backend.
    func setFeaturedPlaylists(_ playlists: [UnifiedPlaylist], userID: UUID?) {
        guard let userID else { return }
        prepare(for: userID)
        featuredPlaylists = Self.normalizedFeaturedPlaylists(playlists)
        hasLoadedFeaturedPlaylists = true
        curationMutationRevision += 1
    }

    /// Publish the full public-profile arrangement immediately after the backend
    /// accepts it, so the profile preview never flashes the old module order.
    func setProfileCuration(
        playlists: [UnifiedPlaylist],
        modules: [ProfileModulePreferenceDTO],
        userID: UUID?
    ) {
        guard let userID else { return }
        prepare(for: userID)
        featuredPlaylists = Self.normalizedFeaturedPlaylists(playlists)
        profileModules = ProfileCurationDTO.normalizedModules(modules)
        hasLoadedFeaturedPlaylists = true
        curationMutationRevision += 1
    }

    /// Preserve the user's chosen order, remove accidental duplicate keys, and
    /// enforce the public-profile contract at the shared-state boundary.
    nonisolated static func normalizedFeaturedPlaylists(_ playlists: [UnifiedPlaylist])
        -> [UnifiedPlaylist] {
        var seen = Set<String>()
        return playlists.filter { seen.insert($0.key).inserted }.prefix(6).map { $0 }
    }

    private func prepare(for userID: UUID) {
        guard ownerID != userID else { return }
        ownerID = userID
        profile = cachedProfile(for: userID)
        featuredPlaylists = []
        profileModules = ProfileModulePreferenceDTO.defaults
        // A cache is only the first paint. Always allow one authoritative refresh
        // for a newly activated app/account session.
        profileLoaded = false
        hasResolvedAccount = profile != nil
        hasLoadedFeaturedPlaylists = false
        profileMutationRevision = 0
        curationMutationRevision = 0
    }

    private func cachedProfile(for userID: UUID) -> ProfileDTO? {
        guard let data = AccountSessionStore.defaultObject(
            forKey: AccountSessionStore.profileCacheKey,
            ownerID: userID
        ) as? Data,
        let decoded = try? JSONDecoder().decode(ProfileDTO.self, from: data),
        decoded.userId == userID else {
            return nil
        }
        return decoded
    }

    private func persistProfile() {
        guard let ownerID, let profile, profile.userId == ownerID,
              let data = try? JSONEncoder().encode(profile) else { return }
        AccountSessionStore.setDefault(
            data,
            forKey: AccountSessionStore.profileCacheKey,
            ownerID: ownerID
        )
    }

    /// Forget the signed-in user's profile (call on sign-out / delete / account switch).
    func reset() {
        ownerID = nil
        profile = nil
        featuredPlaylists = []
        profileModules = ProfileModulePreferenceDTO.defaults
        profileLoaded = false
        hasResolvedAccount = false
        hasLoadedFeaturedPlaylists = false
        profileMutationRevision = 0
        curationMutationRevision = 0
    }
}
