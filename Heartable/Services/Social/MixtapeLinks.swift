import Foundation

struct SharedMixtapeRoute: Identifiable, Equatable {
    let token: String
    var id: String { token }

    static func parse(_ url: URL) -> SharedMixtapeRoute? {
        guard url.scheme?.lowercased() == "heartable", url.host?.lowercased() == "mixtape",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = parts.queryItems?.first(where: { $0.name == "token" })?.value,
              valid(token) else { return nil }
        return SharedMixtapeRoute(token: token)
    }

    static func valid(_ token: String) -> Bool {
        token.utf8.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func webURL(token: String) -> URL? {
        guard valid(token) else { return nil }
        return URL(string: "https://heartable-mixtapes.zlichtman.chatgpt.site/#\(token)")
    }
}

struct MixtapeLinkStatus: Decodable, Sendable {
    let token: String?
    let published_at: String?
}

struct SharedMixtapeSnapshot: Decodable, Sendable {
    let title: String?
    let description: String?
    let cover_url: String?
    let tracks: [Track]

    struct Track: Decodable, Sendable, Identifiable {
        let id: UUID
        let track_name: String?
        let artist: String?
        let track_uri: String?
        let note: String?
        let note_image_url: String?
    }

    static func load(token: String) async throws -> Self {
        guard SharedMixtapeRoute.valid(token), let base = AppConfig.supabaseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("functions/v1/shared-mixtape"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["token": token])
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.resourceUnavailable) }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}
