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
        // Default behavior on purpose (emitLocalSessionAsInitialSession = false):
        // the initial session is emitted only AFTER a refresh attempt, so a session
        // for a deleted/revoked user (refresh fails) resolves to nil and the app
        // drops to the sign-in screen instead of getting stuck "logged in" with a
        // dead session throwing 403s. (We accept the SDK deprecation log line for
        // this correctness.)
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
