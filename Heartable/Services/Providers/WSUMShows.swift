import Foundation

struct WSUMShow: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let host: String
    let startsAt: Date
    let endsAt: Date
    let pageURL: URL

    var favoriteID: String {
        // A live broadcast may use /pl/ while next week's slot uses /show/.
        // Keep favorites attached to the program, not either URL or an airing.
        let identity = "\(title.lowercased())|\(host.lowercased())"
        return "wsum-program-" + Data(identity.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    func isOnAir(at now: Date = Date()) -> Bool { startsAt <= now && now < endsAt }

    var airtime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter.string(from: startsAt) + " CT"
    }

    func matches(_ query: String) -> Bool {
        let text = "WSUM radio \(title) \(host)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { text.contains($0) }
    }
}

/// Public station-owned schedule feed linked by WSUM's Spinitron calendar.
/// These are broadcast times, not a claim that every show has a replay stream.
actor WSUMShows {
    static let shared = WSUMShows()
    private struct Snapshot: Codable { let fetchedAt: Date; let shows: [WSUMShow] }
    private var snapshot: Snapshot?
    private var hydrated = false
    private var inFlight: Task<[WSUMShow]?, Never>?
    private var lastAttempt: Date?
    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("heartable-wsum-schedule.json")

    func load(force: Bool = false) async -> [WSUMShow] {
        if !hydrated {
            if let cacheURL, let data = try? Data(contentsOf: cacheURL) {
                snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
            }
            hydrated = true
        }
        let now = Date()
        if !force, let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < 900 { return snapshot.shows }
        if let inFlight { return await inFlight.value ?? snapshot?.shows ?? [] }
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < 30 { return snapshot?.shows ?? [] }
        lastAttempt = now
        let task = Task<[WSUMShow]?, Never> {
            guard let url = Self.feedURL(now: now) else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return try Self.decode(data)
            } catch { return nil }
        }
        inFlight = task
        let shows = await task.value
        inFlight = nil
        if let shows {
            let fresh = Snapshot(fetchedAt: now, shows: shows)
            snapshot = fresh
            if let cacheURL, let data = try? JSONEncoder().encode(fresh) { try? data.write(to: cacheURL, options: .atomic) }
        }
        return snapshot?.shows ?? []
    }

    func search(_ query: String) async -> [WSUMShow] {
        let now = Date()
        return await load().filter { $0.endsAt > now && $0.matches(query) }
    }

    nonisolated static func feedURL(now: Date) -> URL? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var url = URLComponents(string: "https://spinitron.com/WSUM/calendar-feed")!
        url.queryItems = [URLQueryItem(name: "layout", value: "1"), URLQueryItem(name: "timeslot", value: "30"),
                         URLQueryItem(name: "start", value: formatter.string(from: start)),
                         URLQueryItem(name: "end", value: formatter.string(from: end))]
        return url.url
    }

    nonisolated static func decode(_ data: Data) throws -> [WSUMShow] {
        struct Event: Decodable {
            let title: String
            let text: String?
            let start: String
            let end: String
            let url: String?
            let className: String?
        }
        let events = try JSONDecoder().decode([Event].self, from: data)
        let formatter = ISO8601DateFormatter()
        var seen: Set<String> = []
        return events.compactMap { event -> WSUMShow? in
            guard event.className?.contains("automated") != true,
                  let start = formatter.date(from: event.start), let end = formatter.date(from: event.end), end > start,
                  let rawURL = event.url, let url = URL(string: rawURL), url.scheme == "https",
                  url.host == "spinitron.com",
                  url.path.hasPrefix("/WSUM/show/") || url.path.hasPrefix("/WSUM/pl/") else { return nil }
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let id = "\(start.timeIntervalSince1970):\(title.lowercased())"
            guard seen.insert(id).inserted else { return nil }
            return WSUMShow(id: id, title: title, host: event.text ?? "WSUM", startsAt: start, endsAt: end, pageURL: url)
        }.sorted { $0.startsAt < $1.startsAt }
    }
}
