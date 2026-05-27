import Foundation

/// Coordinates the reminder push/pull cycle with Supabase. M3.2a ships a
/// stub — the actual push/pull logic lands in M3.2b once we add the dirty/
/// pendingDelete columns and the conflict-resolution code.
///
/// The contract `syncNow()` already exposes is what the UI calls today
/// (a "Sync now" button in AccountSheet); the body just becomes real later.
@MainActor
final class SyncEngine: ObservableObject {

    @Published private(set) var isSyncing: Bool = false
    @Published var lastError: String?
    @Published var lastSyncedAt: Date?

    private let database: AppDatabase
    private let sessionStore: SessionStore

    init(database: AppDatabase, sessionStore: SessionStore) {
        self.database = database
        self.sessionStore = sessionStore
    }

    /// Trigger a push+pull. Safe to call concurrently — second invocation
    /// short-circuits while the first is running.
    func syncNow() async {
        guard SupabaseConfig.isConfigured else {
            lastError = "Cloud sync isn't configured in this build."
            return
        }
        guard sessionStore.session != nil else {
            lastError = "Sign in to sync."
            return
        }
        guard !isSyncing else { return }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        // M3.2b: push dirty → upsert; pull updates > lastSyncedAt → merge by updatedAt.
        // For now this is a clean no-op so the AccountSheet "Sync now" button
        // doesn't crash and we can wire up the UI end-to-end before the
        // engine itself lands.
        lastSyncedAt = Date()
    }
}
