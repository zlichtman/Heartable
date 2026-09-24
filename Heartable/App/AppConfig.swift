import Foundation

/// Typed access to build-time configuration. The Supabase host + anon key and the
/// Spotify client id are **public by design** (they ship inside every distributed
/// binary; Row-Level Security protects data), so they're baked in as defaults.
/// A build-time value from `Secrets.xcconfig` / Info.plist overrides a default,
/// but only if it passes a sanity check — that way a missing or mis-pasted
/// Xcode Cloud env var can never break auth (the recurring "Invalid API key").
enum AppConfig {
    // Public-safe defaults (the real project + app values).
    private static let defaultSupabaseHost = "ghmuafydukliccwamkrq.supabase.co"
    private static let defaultSupabaseAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdobXVhZnlkdWtsaWNjd2Fta3JxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzODgwODcsImV4cCI6MjA4OTk2NDA4N30.5ppko4TAesmOHn7CXv6yOPKdOMGVop_645LULcbbDC8"
    private static let defaultSpotifyClientID = "5092e937dcd944d68e7c44b94e114e77"

    /// Reads an Info.plist string, trimming surrounding whitespace/newlines (an
    /// xcconfig value can pick up a stray trailing space or `\n`). Treats an
    /// unsubstituted build variable (a literal `$(NAME)`) as missing so the
    /// baked-in default wins instead of a broken token reaching the network.
    private static func string(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, !v.hasPrefix("$(") else { return nil }
        return v
    }

    /// Decode the `ref` claim (the project id) from a Supabase anon JWT. Used to
    /// reject a configured key that belongs to a DIFFERENT project — the real
    /// cause of the recurring "Invalid API key" (a wrong-project key is JWT-shaped
    /// but the gateway rejects it) — and to keep the host locked to the key.
    private static func jwtRef(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ref = obj["ref"] as? String, !ref.isEmpty else { return nil }
        return ref
    }

    /// The project ref of the baked-in key (nil only in the credential-scrubbed
    /// public snapshot, where the default key is empty).
    private static let defaultRef = jwtRef(defaultSupabaseAnonKey)

    /// The anon key. A build-time override (Secrets.xcconfig / Xcode Cloud env) is
    /// honored ONLY if it is a well-formed Supabase JWT for the SAME project as the
    /// baked-in key; otherwise the known-good baked-in key is used. This makes a
    /// stale, wrong-project, or mis-pasted env var unable to reach the network and
    /// trigger "Invalid API key" — auth always uses a key that matches this project.
    static var supabaseAnonKey: String? {
        if let configured = string("SUPABASE_ANON_KEY"),
           let ref = jwtRef(configured),
           defaultRef == nil || ref == defaultRef {
            return configured
        }
        return defaultSupabaseAnonKey.isEmpty ? nil : defaultSupabaseAnonKey
    }

    /// Project URL kept in lockstep with the active anon key's project ref, so the
    /// host and key can never point at different projects (another "Invalid API
    /// key" cause). Falls back to the configured/baked host only if the key can't
    /// be parsed.
    static var supabaseURL: URL? {
        if let key = supabaseAnonKey, let ref = jwtRef(key) {
            return URL(string: "https://\(ref).supabase.co")
        }
        let configured = string("SUPABASE_HOST")
        let host = (configured?.contains(".supabase.co") == true ? configured! : defaultSupabaseHost)
        return host.isEmpty ? nil : URL(string: "https://\(host)")
    }

    static var spotifyClientID: String? {
        let configured = string("SPOTIFY_CLIENT_ID")
        if let configured, configured.count == 32 { return configured }
        return defaultSpotifyClientID
    }

    static var lastfmAPIKey: String? { string("LASTFM_API_KEY") }
    static var lastfmUser: String? { string("LASTFM_USER") }

    /// Always configured now that the core values have safe defaults.
    static var isConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }
}
