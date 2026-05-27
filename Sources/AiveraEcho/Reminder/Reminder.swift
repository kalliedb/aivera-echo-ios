import Foundation

/// Cross-platform reminder model — mirrors `data/Task.kt` on Android.
struct Reminder: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var clientId: String          // stable per-install ID for sync across devices
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

    init(
        id: UUID = UUID(),
        clientId: String = UUID().uuidString,
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
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.clientId = clientId
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
