import Combine
import Foundation
import GRDB

/// File-backed reminder repository. Replaces the in-memory `ReminderStore` from
/// M1. `reminders` is published via a GRDB `ValueObservation`, so any write
/// (this app or background fires) re-renders SwiftUI automatically.
@MainActor
final class ReminderRepository: ObservableObject {

    @Published private(set) var reminders: [Reminder] = []

    private let database: AppDatabase
    private var observation: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
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

    // MARK: - Writes (async; called from `.task { ... }` in SwiftUI)

    func add(_ reminder: Reminder) async throws {
        try await database.writer.write { db in
            var copy = reminder
            try copy.insert(db)
        }
    }

    func update(_ reminder: Reminder) async throws {
        try await database.writer.write { db in
            var copy = reminder
            copy.updatedAt = Date()
            try copy.update(db)
        }
    }

    func delete(_ reminder: Reminder) async throws {
        let id = reminder.id
        try await database.writer.write { db in
            _ = try Reminder.deleteOne(db, key: id)
        }
    }

    func toggleComplete(_ reminder: Reminder) async throws {
        var copy = reminder
        copy.completed.toggle()
        copy.completedAt = copy.completed ? Date() : nil
        try await update(copy)
    }
}
