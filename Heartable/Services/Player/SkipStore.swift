import Foundation
import Observation

/// Single source of truth for track skip-edit versions (`track_skip_versions`).
/// Every write bumps `revision` so the PlaybackEngine reloads the active version
/// immediately. Ported from the RN skipStore.
@MainActor
@Observable
final class SkipStore {
    /// Bumps on any write so observers reload.
    private(set) var revision = 0

    /// Bump the revision so any observers drop cached skip versions (call on
    /// sign-out / delete / account switch).
    func reset() { revision += 1 }

    func versions(for trackUri: String) async -> [TrackSkipVersionDTO] {
        await BackendAPI.shared.listSkipVersions(trackUri: trackUri)
    }

    func active(for trackUri: String) async -> TrackSkipVersionDTO? {
        await BackendAPI.shared.getActiveSkipVersion(trackUri: trackUri)
    }

    @discardableResult
    func create(trackUri: String, label: String, regions: [SkipRegion]) async -> TrackSkipVersionDTO? {
        let v = try? await BackendAPI.shared.createSkipVersion(
            trackUri: trackUri, label: label, skipRegions: regions)
        revision += 1
        return v ?? nil
    }

    func update(id: UUID, label: String? = nil, regions: [SkipRegion]? = nil) async {
        try? await BackendAPI.shared.updateSkipVersion(id: id, label: label, skipRegions: regions)
        revision += 1
    }

    func delete(id: UUID) async {
        await BackendAPI.shared.deleteSkipVersion(id: id)
        revision += 1
    }

    func setActive(id: UUID, trackUri: String, active: Bool) async {
        try? await BackendAPI.shared.setActiveSkipVersion(id: id, trackUri: trackUri, active: active)
        revision += 1
    }
}
