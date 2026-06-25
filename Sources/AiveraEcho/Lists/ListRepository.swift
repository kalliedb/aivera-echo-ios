import Combine
import Foundation
import GRDB

/// CRUD + observation for `TaskList` + `TaskListItem`. Mirrors Android's
/// TaskListDao / TaskListItemDao split as one Swift type since SwiftUI
/// views consume both via the same @EnvironmentObject.
///
/// Local-only for v1 — sync via Supabase is a follow-up (the schema already
/// carries clientId/dirty/pendingDelete to make that drop-in).
@MainActor
final class ListRepository: ObservableObject {

    /// All non-tombstoned lists, sorted by most-recently-updated.
    @Published private(set) var lists: [TaskList] = []

    private let database: AppDatabase
    private var listsObserverCancellable: AnyDatabaseCancellable?

    init(database: AppDatabase) {
        self.database = database
        startObservingLists()
    }

    // MARK: - Lists

    private func startObservingLists() {
        let observation = ValueObservation.tracking { db -> [TaskList] in
            try TaskList
                .filter(Column("pendingDelete") == false)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
        listsObserverCancellable = observation.start(
            in: database.writer,
            onError: { error in
                print("ListRepository lists observation error: \(error)")
            },
            onChange: { [weak self] lists in
                Task { @MainActor [weak self] in self?.lists = lists }
            }
        )
    }

    /// Observe items for a single list. View uses .task to bind this.
    func itemsObservation(for listId: String) -> ValueObservation<ValueReducers.Fetch<[TaskListItem]>> {
        ValueObservation.tracking { db -> [TaskListItem] in
            try TaskListItem
                .filter(Column("listId") == listId)
                .order(Column("orderIndex").asc, Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    @discardableResult
    func addList(name: String, type: ListType = .custom) async throws -> TaskList {
        let list = TaskList(name: name, type: type)
        // Re-bind inside the writer closure so the mutating insert(db) is
        // called on a fresh `var` local to the closure — avoids Swift 6
        // captured-var-mutation diagnostic, same pattern as ReminderRepository.
        try await database.writer.write { db in
            var row = list
            try row.insert(db)
        }
        return list
    }

    func renameList(_ list: TaskList, to newName: String) async throws {
        let snapshot = TaskList(
            id: list.id, clientId: list.clientId, name: newName, type: list.type,
            createdAt: list.createdAt, updatedAt: Date(),
            dirty: true, pendingDelete: list.pendingDelete
        )
        try await database.writer.write { db in
            var row = snapshot
            try row.update(db)
        }
    }

    func deleteList(_ list: TaskList) async throws {
        // Soft delete via tombstone — matches Android's pendingDelete pattern.
        // Items cascade-delete naturally once a sync engine hard-deletes the
        // parent; for now they're orphaned-but-hidden behind the list filter.
        let snapshot = TaskList(
            id: list.id, clientId: list.clientId, name: list.name, type: list.type,
            createdAt: list.createdAt, updatedAt: Date(),
            dirty: true, pendingDelete: true
        )
        try await database.writer.write { db in
            var row = snapshot
            try row.update(db)
        }
    }

    // MARK: - Items

    @discardableResult
    func addItem(to list: TaskList, text: String) async throws -> TaskListItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "ListRepository", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Item text is empty"])
        }
        let item = TaskListItem(listId: list.id, text: trimmed)
        let listId = list.id
        try await database.writer.write { db in
            let maxIndex: Int = try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(orderIndex), -1) + 1
                    FROM task_list_items
                    WHERE listId = ?
                """,
                arguments: [listId]
            ) ?? 0
            var row = item
            row.orderIndex = maxIndex
            try row.insert(db)
            // Bump list's updatedAt so the index re-orders to show the most
            // recently-touched list first.
            try TaskList
                .filter(Column("id") == listId)
                .updateAll(db, Column("updatedAt").set(to: Date()))
        }
        return item
    }

    func setChecked(_ item: TaskListItem, checked: Bool) async throws {
        let snapshot = TaskListItem(
            id: item.id, listId: item.listId, text: item.text,
            checked: checked, orderIndex: item.orderIndex,
            createdAt: item.createdAt, updatedAt: Date()
        )
        try await database.writer.write { db in
            var row = snapshot
            try row.update(db)
        }
    }

    func deleteItem(_ item: TaskListItem) async throws {
        try await database.writer.write { db in
            _ = try TaskListItem
                .filter(Column("id") == item.id)
                .deleteAll(db)
        }
    }

    /// Wipe everything — used by Settings → Delete all data.
    func wipeAll() async {
        do {
            try await database.writer.write { db in
                _ = try TaskListItem.deleteAll(db)
                _ = try TaskList.deleteAll(db)
            }
        } catch {
            print("ListRepository.wipeAll failed: \(error)")
        }
    }
}
