import Foundation

/// Transport controls used by PlayerStore (the adapter's port focused on reads +
/// starting playback; these cover pause/skip/seek on the active Spotify device).
extension SpotifyAPI {
    static func control(_ path: String, method: String = "PUT", token: String) async throws {
        guard let url = URL(string: "https://api.spotify.com/v1\(path)") else {
            throw ProviderError("Invalid Spotify control.")
        }
        let (_, response) = try await HTTPClient.send(
            url, method: method,
            headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"]
        )
        switch response.statusCode {
        case 200..<300: return
        case 404: throw NoActiveDeviceError()
        case 401: throw ProviderError("Reconnect Spotify in Music Services.")
        case 403: throw ProviderError("Spotify didn’t allow playback control. Spotify Premium is required.")
        case 429: throw ProviderError("Spotify needs a moment. Try the control again shortly.")
        default: throw ProviderError("Spotify couldn’t complete that playback command. Please try again.")
        }
    }

    static func pause(token: String) async { try? await control("/me/player/pause", token: token) }
}
