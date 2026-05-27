import Foundation
import GRDB

/// Cross-platform reminder model — mirrors `data/Task.kt` on Android.
/// Persisted in SQLite via GRDB; the primary key is a stable UUID string so
/// IDs are globally unique and sync-friendly.
struct Reminder: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var clientId: String          // separate id for cross-device sync (defaults to `id`)
    var text: String
    var triggerAt: Date
    var completed: Bool
    var completedAt: Date?
    var audioPath: String?
    var recurrence: Recurrence
    var triggerType: TriggerType
    var latitude: Double?
    var longitude: Double?
    var radiusMeters: Double?
    var placeLabel: String?
    var updatedAt: Date

    // Sync metadata (added in v2 migration). `dirty` flags rows that haven't
    // been pushed yet; `pendingDelete` is the tombstone marker — soft-deleted
    // locally, hard-deleted once the push is acknowledged by Supabase.
    var dirty: Bool
    var pendingDelete: Bool

    init(
        id: String = UUID().uuidString,
        clientId: String? = nil,
        text: String,
        triggerAt: Date,
        completed: Bool = false,
        completedAt: Date? = nil,
        audioPath: String? = nil,
        recurrence: Recurrence = .none,
        triggerType: TriggerType = .time,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double? = nil,
        placeLabel: String? = nil,
        updatedAt: Date = Date(),
        dirty: Bool = false,
        pendingDelete: Bool = false
    ) {
        self.id = id
        self.clientId = clientId ?? id
        self.text = text
        self.triggerAt = triggerAt
        self.completed = completed
        self.completedAt = completedAt
        self.audioPath = audioPath
        self.recurrence = recurrence
        self.triggerType = triggerType
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.placeLabel = placeLabel
        self.updatedAt = updatedAt
        self.dirty = dirty
        self.pendingDelete = pendingDelete
    }
}

enum Recurrence: String, Codable, CaseIterable {
    case none = "NONE"
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"

    var label: String {
        switch self {
        case .none:    return "One-off"
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

enum TriggerType: String, Codable {
    case time = "TIME"
    case location = "LOCATION"
}

// MARK: - GRDB persistence
extension Reminder: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "reminders" }
}
