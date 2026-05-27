import Foundation

/// Wire-format reminder for Supabase REST. Snake_case columns match the
/// schema Android writes to, so sync is bidirectional across platforms.
/// Dates are encoded as ISO-8601 strings (Postgres timestamptz parses them
/// natively) so we don't depend on supabase-swift's decoder configuration.
struct ReminderDto: Codable, Equatable {

    let client_id: String
    let user_id: String?
    let text: String
    let trigger_at: String           // ISO-8601 with fractional seconds
    let trigger_type: String
    let recurrence: String
    let completed: Bool
    let completed_at: String?
    let latitude: Double?
    let longitude: Double?
    let radius_meters: Double?
    let place_label: String?
    let updated_at: String
    let deleted: Bool
    let deleted_at: String?

    // ISO-8601 formatter shared across encode/decode. Fractional seconds match
    // Postgres timestamptz output (e.g. "2026-05-27T10:14:32.123456+00:00").
    static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Mapping
extension ReminderDto {

    init(from reminder: Reminder, userId: String) {
        let now = Date()
        self.client_id     = reminder.clientId
        self.user_id       = userId
        self.text          = reminder.text
        self.trigger_at    = Self.dateFormatter.string(from: reminder.triggerAt)
        self.trigger_type  = reminder.triggerType.rawValue
        self.recurrence    = reminder.recurrence.rawValue
        self.completed     = reminder.completed
        self.completed_at  = reminder.completedAt.map { Self.dateFormatter.string(from: $0) }
        self.latitude      = reminder.latitude
        self.longitude     = reminder.longitude
        self.radius_meters = reminder.radiusMeters
        self.place_label   = reminder.placeLabel
        self.updated_at    = Self.dateFormatter.string(from: reminder.updatedAt)
        self.deleted       = reminder.pendingDelete
        self.deleted_at    = reminder.pendingDelete
            ? Self.dateFormatter.string(from: reminder.updatedAt)
            : nil
        _ = now  // silence unused (kept for symmetry if we need created_at later)
    }

    /// Convert into a `Reminder`. Preserves the existing local `id` if we
    /// already had this client_id locally; otherwise generates a new one.
    func toReminder(existingId: String? = nil) -> Reminder {
        let triggerAtDate = Self.dateFormatter.date(from: trigger_at) ?? Date()
        let completedAtDate = completed_at.flatMap { Self.dateFormatter.date(from: $0) }
        let updatedAtDate = Self.dateFormatter.date(from: updated_at) ?? Date()

        return Reminder(
            id:           existingId ?? UUID().uuidString,
            clientId:     client_id,
            text:         text,
            triggerAt:    triggerAtDate,
            completed:    completed,
            completedAt:  completedAtDate,
            audioPath:    nil,                                     // audio is local-only
            recurrence:   Recurrence(rawValue: recurrence) ?? .none,
            triggerType:  TriggerType(rawValue: trigger_type) ?? .time,
            latitude:     latitude,
            longitude:    longitude,
            radiusMeters: radius_meters,
            placeLabel:   place_label,
            updatedAt:    updatedAtDate,
            dirty:        false,
            pendingDelete: false
        )
    }

    var updatedAtDate: Date? { Self.dateFormatter.date(from: updated_at) }
}
