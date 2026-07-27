import Foundation
import Observation

/// Navigation value used to open the existing Add Friend flow from anywhere in
/// the authenticated app.
struct AddFriendRoute: Hashable {}

/// Holds a pending friend-invite code parsed from a `heartable://add-friend?code=…`
/// deep link. The request id changes for every received URL (including the same
/// invite twice), allowing the app shell to actively navigate while already open.
/// AddFriendView consumes + clears the code after navigation.
@MainActor
@Observable
final class FriendLinks {
    private(set) var pendingCode: String?
    private(set) var routeRequestID: UUID?
    private(set) var relationshipRevision = 0

    func handle(_ url: URL) {
        guard let code = Self.inviteCode(from: url) else { return }
        pendingCode = code
        routeRequestID = UUID()
    }

    func take() -> String? {
        defer { pendingCode = nil }
        return pendingCode
    }

    /// Invalidate every social surface after a relationship mutation. Views use
    /// this as a task identity, so an underlying list refreshes even while a
    /// detail screen is still on top of it.
    func markRelationshipsChanged() {
        relationshipRevision &+= 1
    }

    /// Clear device-scoped navigation intent when the authenticated shell is
    /// unmounted for an account transition.
    func resetForAccountTransition() {
        pendingCode = nil
        routeRequestID = nil
        relationshipRevision &+= 1
    }

    /// Pure parser kept separate from navigation state for focused tests.
    nonisolated static func inviteCode(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "heartable",
              url.host?.lowercased() == "add-friend" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let raw = components?.queryItems?
            .first(where: { $0.name.lowercased() == "code" })?.value else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }
}
