import Foundation

/// Tiny async URLSession wrapper for the provider adapters. JSON decode helper +
/// raw request. Honors a simple Retry-After backoff on 429.
enum HTTPClient {
    static let json: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// snake_case-configured decoder for adapters whose payloads use snake_case
    /// keys. Existing callers keep passing `json`; new adapters can opt in.
    static let snakeCase: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    enum Failure: LocalizedError {
        case status(Int)
        case transport(Error)
        var errorDescription: String? {
            switch self {
            case .status(let code): "Request failed (\(code))."
            case .transport(let e): e.localizedDescription
            }
        }
    }

    // MARK: - Retry tuning

    /// Total tries (initial + retries) before giving up.
    private static let maxAttempts = 3
    /// Per-request network timeout.
    private static let requestTimeout: TimeInterval = 20
    /// Ceiling for an honored `Retry-After`, so a hostile header can't stall us.
    private static let maxRetryAfter: TimeInterval = 30
    /// Cap for the exponential fallback backoff.
    private static let backoffCap: TimeInterval = 3

    /// GET + decode JSON. `decoder` lets callers pass a snake_case-configured one.
    static func getJSON<T: Decodable>(
        _ url: URL,
        headers: [String: String] = [:],
        decoder: JSONDecoder = json
    ) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = requestTimeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await perform(req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw Failure.status(code)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Raw request returning data + response (used for redirects/stream probes).
    static func send(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = requestTimeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await perform(req)
        return (data, resp as? HTTPURLResponse ?? HTTPURLResponse())
    }

    // MARK: - Retry engine

    /// Issues `req`, retrying up to `maxAttempts` total on HTTP 429/503 (honoring
    /// `Retry-After`) and on transient transport errors, with exponential backoff.
    /// Backoff waits use `Task.sleep`, never wall-clock arithmetic.
    private static func perform(_ req: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                try Task.checkCancellation()
                if let http = resp as? HTTPURLResponse,
                   http.statusCode == 429 || http.statusCode == 503,
                   attempt < maxAttempts - 1 {
                    let delay = retryAfterDelay(http) ?? backoff(attempt)
                    try await Task.sleep(nanoseconds: nanoseconds(delay))
                    attempt += 1
                    continue
                }
                return (data, resp)
            } catch {
                try Task.checkCancellation()
                if isTransient(error), attempt < maxAttempts - 1 {
                    try await Task.sleep(nanoseconds: nanoseconds(backoff(attempt)))
                    attempt += 1
                    continue
                }
                throw Failure.transport(error)
            }
        }
    }

    /// Transient transport errors worth a retry (timeouts / dropped connections).
    private static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    /// `Retry-After` as seconds: integer form or an HTTP-date, clamped to a cap.
    private static func retryAfterDelay(_ resp: HTTPURLResponse) -> TimeInterval? {
        guard let raw = resp.value(forHTTPHeaderField: "Retry-After") else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(value) {
            return min(max(seconds, 0), maxRetryAfter)
        }
        // HTTP-date (RFC 1123). Parsed with a POSIX/GMT formatter; the only
        // wall-clock use is measuring how far in the future the date is.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            let delay = date.timeIntervalSinceNow
            return delay > 0 ? min(delay, maxRetryAfter) : 0
        }
        return nil
    }

    /// Exponential fallback backoff: ~0.5s, 1s, 2s, capped.
    private static func backoff(_ attempt: Int) -> TimeInterval {
        min(0.5 * pow(2, Double(attempt)), backoffCap)
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(seconds, 0) * 1_000_000_000)
    }
}
