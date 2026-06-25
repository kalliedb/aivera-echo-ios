import Foundation
import GRDB

/// Pre-configured list type — drives icon + default name when creating from
/// the "+ New list" entry. Mirrors Android's data/TaskList.kt enum exactly so
/// future sync between platforms speaks the same vocabulary.
enum ListType: String, Codable, CaseIterable {
    case shopping = "SHOPPING"
    case packing  = "PACKING"
    case ideas    = "IDEAS"
    case custom   = "CUSTOM"

    var label: String {
        switch self {
        case .shopping: return "Shopping"
        case .packing:  return "Packing"
        case .ideas:    return "Ideas"
        case .custom:   return "Custom"
        }
    }

    /// SF Symbol shown alongside the list name in the Lists index.
    var symbol: String {
        switch self {
        case .shopping: return "cart.fill"
        case .packing:  return "suitcase.fill"
        case .ideas:    return "lightbulb.fill"
        case .custom:   return "list.bullet.rectangle"
        }
    }
}

/// A user-owned list of items — shopping list, packing list, ideas board.
/// Distinct from `Reminder`: a list has no trigger time, no geofence, no
/// audio. Its items live in `TaskListItem` and reference this row via
/// `TaskListItem.listId`.
///
/// Sync bookkeeping mirrors Reminder (clientId / updatedAt / dirty /
/// pendingDelete) so the existing SyncEngine pattern can be extended without
/// another schema change once iOS Lists sync ships.
struct TaskList: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var clientId: String
    var name: String
    var type: ListType
    var createdAt: Date
    var updatedAt: Date
    var dirty: Bool
    var pendingDelete: Bool

    init(
        id: String = UUID().uuidString,
        clientId: String? = nil,
        name: String,
        type: ListType = .custom,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.id = id
        self.clientId = clientId ?? id
        self.name = name
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dirty = dirty
        self.pendingDelete = pendingDelete
    }
}

/// A single line in a TaskList. The list itself is a container; items carry
/// the check state and ordering.
///
/// On the parent list delete, items are cascade-removed by the foreign key.
/// orderIndex is manually managed (not auto-derived) so reordering by drag is
/// a single UPDATE rather than a renumber pass. New items go to the end via
/// `MAX(orderIndex) + 1`.
struct TaskListItem: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var listId: String
    var text: String
    var checked: Bool
    var orderIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        listId: String,
        text: String,
        checked: Bool = false,
        orderIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.listId = listId
        self.text = text
        self.checked = checked
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB persistence

extension TaskList: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "task_lists" }
}

extension TaskListItem: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "task_list_items" }
}
