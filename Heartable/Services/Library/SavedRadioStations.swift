import Foundation
import Observation

/// User choices, not a cache: survive refresh/cache clearing and normal sign-out.
/// Only canonical WSUM IDs are stored; arbitrary shared stream URLs are rejected.
@MainActor @Observable
final class SavedRadioStations {
    static let storageKey = "heartable.radio.savedStations.v1"
    private(set) var ids: Set<String> = []
    private var ownerID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var stations: [FeaturedRadioStations.Station] { FeaturedRadioStations.all.filter { ids.contains($0.id) } }
    func contains(_ id: String) -> Bool { ids.contains(id) }

    func activate(ownerID: UUID?) {
        guard self.ownerID != ownerID else { return }
        self.ownerID = ownerID
        guard let ownerID else { ids = []; return }
        let key = AccountSessionStore.scopedKey(Self.storageKey, ownerID: ownerID)
        ids = Set(defaults.stringArray(forKey: key) ?? []).filter(Self.isValid)
    }

    func toggle(_ id: String) {
        guard let ownerID, Self.isValid(id) else { return }
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        defaults.set(ids.sorted(), forKey: AccountSessionStore.scopedKey(Self.storageKey, ownerID: ownerID))
    }

    func clear(ownerID: UUID) {
        defaults.removeObject(forKey: AccountSessionStore.scopedKey(Self.storageKey, ownerID: ownerID))
        if self.ownerID == ownerID { ids = [] }
    }

    private static func isValid(_ id: String) -> Bool {
        FeaturedRadioStations.station(id: id) != nil ||
            (id.hasPrefix("wsum-program-") && id.count > 13 && id.count < 512 &&
             id.dropFirst(13).allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}
