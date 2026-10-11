import Foundation

struct SpotifyPlaylistHTTPError: Error, Sendable {
    let status: Int
}

enum SpotifyPlaylistFailure {
    static func message(for error: Error) -> String {
        if let error = error as? SpotifyPlaylistHTTPError {
            switch error.status {
            case 401:
                return "Your Spotify session expired (401). Reconnect Spotify in Music Services."
            case 403:
                return "Spotify denied access to this playlist (403). Check that the linked Spotify account owns it or is a collaborator. If it does, reconnect Spotify to renew playlist permissions."
            case 404:
                return "Spotify couldn’t find this playlist or doesn’t allow this account to read it (404). Check it in Spotify."
            default:
                return "Spotify couldn’t load this playlist (\(error.status)). Try again shortly."
            }
        }
        if let limited = error as? SpotifyReadBackoff.Limited {
            let minutes = max(1, Int(ceil(limited.retryAfter / 60)))
            return "Spotify is limiting requests. Try again in about \(minutes) minutes. Saved tracks are retained."
        }
        if error is DecodingError { return "Spotify returned a playlist response Heartable couldn’t read. A diagnostic was saved in Profile → Account → Diagnostics." }
        if let network = error as? URLError {
            return network.code == .notConnectedToInternet
                ? "You’re offline. Connect to the internet and retry."
                : "The connection to Spotify failed. Check your connection and retry."
        }
        return "Spotify couldn’t load the tracks. Retry, or reconnect Spotify in Music Services if this continues."
    }

    static func record(_ error: Error) async {
        let code: String
        if let http = error as? SpotifyPlaylistHTTPError { code = "http_\(http.status)" }
        else if error is SpotifyReadBackoff.Limited { code = "rate_limited" }
        else if error is DecodingError { code = "decode" }
        else if let network = error as? URLError { code = "network_\(network.code.rawValue)" }
        else { code = "session_or_provider" }
        // No provider IDs, playlist names, URLs, response bodies, or credentials.
        await DiagnosticsStore.shared.recordProviderFailure(code: code, summary: message(for: error))
    }
}
