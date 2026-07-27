import Foundation

/// Transport controls used by PlayerStore (the adapter's port focused on reads +
/// starting playback; these cover pause/skip/seek on the active Spotify device).
extension SpotifyAPI {
    private static func control(_ path: String, method: String, token: String) async {
        guard let url = URL(string: "https://api.spotify.com/v1\(path)") else { return }
        _ = try? await HTTPClient.send(
            url, method: method,
            headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"]
        )
    }

    static func pause(token: String) async { await control("/me/player/pause", method: "PUT", token: token) }
    static func resume(token: String) async { await control("/me/player/play", method: "PUT", token: token) }
    static func next(token: String) async { await control("/me/player/next", method: "POST", token: token) }
    static func previous(token: String) async { await control("/me/player/previous", method: "POST", token: token) }
    static func seek(token: String, positionMs: Int) async {
        await control("/me/player/seek?position_ms=\(max(0, positionMs))", method: "PUT", token: token)
    }
}
