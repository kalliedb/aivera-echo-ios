import Foundation

/// Snapshot of the signed-in user. Kept minimal — userId and email are all the
/// UI needs. Tokens are persisted by supabase-swift in Keychain.
struct AppSession: Equatable, Codable {
    let userId: String
    let email: String
}
