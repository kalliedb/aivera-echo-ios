import Foundation
import Supabase

/// Project URL + anon key, read from Info.plist (populated by project.yml).
/// The anon key is designed to be public-readable — Row-Level Security on
/// Supabase protects the actual data. Committing it is intentional.
enum SupabaseConfig {

    static let url: URL = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String) ?? ""
        return URL(string: raw) ?? URL(string: "https://example.supabase.co")!
    }()

    static let anonKey: String = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String) ?? ""
        // Default placeholder set in project.yml — treat as "not configured".
        if raw.hasPrefix("PASTE_") { return "" }
        return raw
    }()

    /// Becomes false when Info.plist is missing the anon key. The UI shows a
    /// "Cloud sync isn't configured" message instead of attempting requests.
    static var isConfigured: Bool { !anonKey.isEmpty }

    /// Single shared client. supabase-swift persists sessions to Keychain
    /// automatically, so sign-in survives app relaunch.
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: url,
        supabaseKey: anonKey
    )
}
