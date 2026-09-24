import Foundation
import Supabase

/// The one configured Supabase client for the whole app. Builds from AppConfig
/// (Secrets.xcconfig). Falls back to a placeholder URL when unconfigured so the
/// app can still launch and show a config-needed screen (gated by
/// `AppConfig.isConfigured`).
enum SupabaseClientProvider {
    static let shared: SupabaseClient = {
        let url = AppConfig.supabaseURL ?? URL(string: "https://placeholder.supabase.co")!
        let key = AppConfig.supabaseAnonKey ?? "placeholder-anon-key"
        // Restore the durable local session immediately. This is Supabase Swift's
        // next-major behavior and lets Heartable activate the matching provider
        // vault before network refresh finishes. Expired sessions are refreshed in
        // the background; a genuinely revoked session still emits signedOut.
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: .init(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }()
}
