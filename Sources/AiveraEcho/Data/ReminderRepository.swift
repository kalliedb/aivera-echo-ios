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

    // MARK: - Writes

    func add(_ reminder: Reminder) async throws {
        try await database.writer.write { db in
            var copy = reminder
            try copy.insert(db)
        }
        await arm(reminder)
    }

    func update(_ reminder: Reminder) async throws {
        var copy = reminder
        copy.updatedAt = Date()
        try await database.writer.write { db in
            try copy.update(db)
        }
        await arm(copy)
    }

    func delete(_ reminder: Reminder) async throws {
        let id = reminder.id
        try await database.writer.write { db in
            _ = try Reminder.deleteOne(db, key: id)
        }
        disarm(reminderId: id)
        // Expose for the UndoSnackbar. UI clears this via clearUndo() after the
        // 5-second window, or restores via undoDelete().
        recentlyDeleted = reminder
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

    /// Re-insert the most recently deleted reminder and re-arm its notification.
    func undoDelete() async {
        guard let r = recentlyDeleted else { return }
        recentlyDeleted = nil
        try? await add(r)
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
