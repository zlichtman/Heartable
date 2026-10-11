import Foundation
import Observation

/// App-wide revision counter for the viewer's friendships. Any screen that
/// changes a relationship (request sent, accepted, declined, canceled, removed)
/// bumps it; social lists use it as a task identity, so an underlying list
/// refreshes even while a detail screen is still on top of it.
@MainActor
@Observable
final class FriendRelationships {
    private(set) var revision = 0

    func markChanged() {
        revision &+= 1
    }
}
