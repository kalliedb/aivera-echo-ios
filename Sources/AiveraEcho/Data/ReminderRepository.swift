import Combine
import Foundation
import GRDB

/// File-backed reminder repository. Each write to the DB also keeps the
/// system notification queue in sync (schedule/cancel/reschedule) via the
/// injected `NotificationScheduler`.
@MainActor
final class ReminderRepository: ObservableObject {

    @Published private(set) var reminders: [Reminder] = []

    /// The most recently swipe-deleted reminder. Cleared after the undo window
    /// expires or the user taps undo. Drives the UndoSnackbar UI.
    @Published private(set) var recentlyDeleted: Reminder?

    private let database: AppDatabase
    private let scheduler: NotificationScheduler?
    private let geofenceManager: GeofenceManager?
    private var observation: AnyDatabaseCancellable?

    init(
        database: AppDatabase,
        scheduler: NotificationScheduler? = nil,
        geofenceManager: GeofenceManager? = nil
    ) {
        self.database = database
        self.scheduler = scheduler
        self.geofenceManager = geofenceManager
        observe()
    }

    private func observe() {
        let observation = ValueObservation
            .tracking { db -> [Reminder] in
                try Reminder
                    .filter(Column("pendingDelete") == false)  // hide tombstoned rows
                    .order(Column("completed").asc, Column("triggerAt").asc)
                    .fetchAll(db)
            }
            .removeDuplicates()

        self.observation = observation.start(
            in: database.writer,
            scheduling: .immediate,
            onError: { error in
                print("ReminderRepository observation error: \(error)")
            },
            onChange: { [weak self] reminders in
                self?.reminders = reminders
            }
        )
    }

    // MARK: - Reads
    func findById(_ id: String) async throws -> Reminder? {
        try await database.writer.read { db in
            try Reminder.fetchOne(db, key: id)
        }
    }

    func findByClientId(_ clientId: String) async throws -> Reminder? {
        try await database.writer.read { db in
            try Reminder.filter(Column("clientId") == clientId).fetchOne(db)
        }
    }

    /// Rows that need pushing (locally edited or tombstoned).
    func getDirty() async throws -> [Reminder] {
        try await database.writer.read { db in
            try Reminder.filter(Column("dirty") == true).fetchAll(db)
        }
    }

    // MARK: - Local writes (mark dirty so the next sync pushes)

    func add(_ reminder: Reminder) async throws {
        var copy = reminder
        copy.dirty = true
        try await database.writer.write { db in
            try copy.insert(db)
        }
        await arm(copy)
    }

    func update(_ reminder: Reminder) async throws {
        var copy = reminder
        copy.dirty = true
        copy.updatedAt = Date()
        try await database.writer.write { db in
            try copy.update(db)
        }
        await arm(copy)
    }

    /// Soft-delete: marks the row pendingDelete + dirty. The row vanishes from
    /// the UI (filtered in observe()), the next sync pushes the tombstone, and
    /// the SyncEngine hard-deletes locally once Supabase ACKs the push.
    func delete(_ reminder: Reminder) async throws {
        var soft = reminder
        soft.pendingDelete = true
        soft.dirty = true
        soft.updatedAt = Date()
        try await database.writer.write { db in
            try soft.update(db)
        }
        disarm(reminderId: reminder.id)
        recentlyDeleted = reminder
    }

    // MARK: - Sync application (do NOT re-mark dirty — those rows came from server)

    /// Hard-delete a row by primary key. Used after a tombstone push is ACKed,
    /// or when a remote `deleted=true` arrives during pull.
    func hardDelete(id: String) async throws {
        try await database.writer.write { db in
            _ = try Reminder.deleteOne(db, key: id)
        }
        disarm(reminderId: id)
    }

    /// Wipe every row. Used by Settings → Delete my data.
    func wipeAll() async {
        let ids = (try? await database.writer.read { db in
            try Reminder.fetchAll(db).map(\.id)
        }) ?? []
        for id in ids { disarm(reminderId: id) }
        try? await database.writer.write { db in
            _ = try Reminder.deleteAll(db)
        }
    }

    /// Clear dirty flag after a successful push (the row is now in sync).
    func clearDirty(id: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE \(Reminder.databaseTableName) SET dirty = 0 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Insert a row from sync without flipping dirty.
    func applyRemoteInsert(_ reminder: Reminder) async throws {
        var copy = reminder
        copy.dirty = false
        copy.pendingDelete = false
        try await database.writer.write { db in
            try copy.insert(db)
        }
        await arm(copy)
    }

    /// Update a row from sync without flipping dirty.
    func applyRemoteUpdate(_ reminder: Reminder) async throws {
        var copy = reminder
        copy.dirty = false
        copy.pendingDelete = false
        try await database.writer.write { db in
            try copy.update(db)
        }
        await arm(copy)
    }

    // MARK: - Trigger orchestration
    /// Tell the right subsystem to (re-)register triggers for this reminder.
    /// Each subsystem internally filters by triggerType + completed, so we
    /// can naively call both for every write.
    private func arm(_ reminder: Reminder) async {
        await scheduler?.schedule(reminder)
        geofenceManager?.register(reminder)
    }

    /// Symmetric cancel for delete.
    private func disarm(reminderId: String) {
        scheduler?.cancel(reminderId: reminderId)
        geofenceManager?.unregister(reminderId: reminderId)
    }

    /// Restore the most recently deleted reminder. The DB row still exists
    /// (soft-deleted via pendingDelete), so just flip the flag + reschedule.
    func undoDelete() async {
        guard let r = recentlyDeleted else { return }
        recentlyDeleted = nil

        var restored = r
        restored.pendingDelete = false
        restored.dirty = true
        restored.updatedAt = Date()
        try? await database.writer.write { db in
            try restored.update(db)
        }
        await arm(restored)
    }

    /// Drop the undo state without restoring (snackbar timed out).
    func clearUndo() {
        recentlyDeleted = nil
    }

    func toggleComplete(_ reminder: Reminder) async throws {
        var copy = reminder
        copy.completed.toggle()
        copy.completedAt = copy.completed ? Date() : nil
        try await update(copy)
    }

    /// Snooze by N minutes from now. Used by notification action handlers.
    func snooze(_ reminder: Reminder, minutes: Int) async throws {
        var copy = reminder
        copy.completed = false
        copy.completedAt = nil
        copy.triggerAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        try await update(copy)
    }
}
