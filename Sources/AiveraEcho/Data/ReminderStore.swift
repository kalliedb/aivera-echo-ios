import Foundation
import Combine

/// In-memory reminder store. Later (M2) this becomes a GRDB+SQLCipher-backed
/// repository — same interface so the views don't change.
@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [Reminder] = []

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        sort()
    }

    func update(_ reminder: Reminder) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[idx] = reminder
        sort()
    }

    func delete(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
    }

    func toggleComplete(_ reminder: Reminder) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[idx].completed.toggle()
        reminders[idx].completedAt = reminders[idx].completed ? Date() : nil
        reminders[idx].updatedAt = Date()
    }

    private func sort() {
        // Mirror Android: incomplete first, then by triggerAt ascending.
        reminders.sort { a, b in
            if a.completed != b.completed { return !a.completed && b.completed }
            return a.triggerAt < b.triggerAt
        }
    }
}
