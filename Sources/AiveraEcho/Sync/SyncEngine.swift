import Foundation
import Supabase

/// Push locally-changed reminders, then pull remote changes since the last sync.
/// Conflicts resolve last-write-wins by `updatedAt`. Mirrors Android's SyncEngine.kt.
@MainActor
final class SyncEngine: ObservableObject {

    @Published private(set) var isSyncing: Bool = false
    @Published var lastError: String?
    @Published var lastSyncedAt: Date?

    private let database: AppDatabase
    private let repository: ReminderRepository
    private let sessionStore: SessionStore
    private let settingsStore: SettingsStore
    private let client = SupabaseConfig.shared

    private let lastSyncedAtKey = "echo.lastSyncedAt"

    init(
        database: AppDatabase,
        repository: ReminderRepository,
        sessionStore: SessionStore,
        settingsStore: SettingsStore
    ) {
        self.database = database
        self.repository = repository
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.lastSyncedAt = UserDefaults.standard.object(forKey: lastSyncedAtKey) as? Date
    }

    /// Trigger a push+pull. Safe to call concurrently — a second invocation
    /// short-circuits while the first is in flight. No-op when the user has
    /// turned off cloud sync in Settings (push side stays dirty for later).
    func syncNow() async {
        guard SupabaseConfig.isConfigured else {
            lastError = "Cloud sync isn't configured in this build."
            return
        }
        guard settingsStore.settings.cloudSyncEnabled else {
            // Don't surface an error here — user-chosen off state is fine.
            return
        }
        guard let session = sessionStore.session else {
            lastError = "Sign in to sync."
            return
        }
        guard !isSyncing else { return }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            try await push(userId: session.userId)
            try await pull()
            let now = Date()
            UserDefaults.standard.set(now, forKey: lastSyncedAtKey)
            lastSyncedAt = now
        } catch {
            let nsErr = error as NSError
            lastError = nsErr.localizedDescription
            print("SyncEngine error: \(error)")
        }
    }

    // MARK: - Push

    private func push(userId: String) async throws {
        let dirty = try await repository.getDirty()
        guard !dirty.isEmpty else { return }

        let dtos = dirty.map { ReminderDto(from: $0, userId: userId) }
        try await client
            .from("reminders")
            .upsert(dtos, onConflict: "user_id,client_id")
            .execute()

        // Acknowledge each pushed row: clear dirty, or hard-delete the tombstone.
        for reminder in dirty {
            if reminder.pendingDelete {
                try await repository.hardDelete(id: reminder.id)
            } else {
                try await repository.clearDirty(id: reminder.id)
            }
        }
    }

    // MARK: - Pull

    private func pull() async throws {
        let since = lastSyncedAt ?? Date(timeIntervalSince1970: 0)
        let sinceStr = ReminderDto.dateFormatter.string(from: since)

        let response: [ReminderDto] = try await client
            .from("reminders")
            .select()
            .gt("updated_at", value: sinceStr)
            .execute()
            .value

        for dto in response {
            await applyRemote(dto)
        }
    }

    private func applyRemote(_ dto: ReminderDto) async {
        do {
            let local = try await repository.findByClientId(dto.client_id)
            let remoteUpdated = dto.updatedAtDate ?? Date()

            // 1. Local has unsynced edits newer than this remote row → keep local.
            //    It'll be pushed on the next cycle.
            if let local, local.dirty, local.updatedAt > remoteUpdated { return }

            // 2. Already in sync (e.g. we just pushed this row, server echoed it back).
            if let local, !local.dirty, local.updatedAt == remoteUpdated { return }

            // 3. Remote tombstone → hard-delete locally.
            if dto.deleted {
                if let local { try await repository.hardDelete(id: local.id) }
                return
            }

            // 4. Apply.
            let merged = dto.toReminder(existingId: local?.id)
            if local == nil {
                try await repository.applyRemoteInsert(merged)
            } else {
                try await repository.applyRemoteUpdate(merged)
            }
        } catch {
            print("applyRemote error for \(dto.client_id): \(error)")
        }
    }
}
