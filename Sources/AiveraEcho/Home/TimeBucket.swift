import Foundation

/// Time-grouped sections for the Home reminder list (FR-HOME-006).
///
/// Order matches the rendering order top-to-bottom: Overdue first (only when
/// non-empty), then Today, Tomorrow, This Week, Later (anything beyond this
/// week), and finally the collapsible Recently Done strip.
enum TimeBucket: String, CaseIterable {
    case overdue
    case today
    case tomorrow
    case thisWeek
    case later
    case recentlyDone

    var title: String {
        switch self {
        case .overdue:      return "Overdue"
        case .today:        return "Today"
        case .tomorrow:     return "Tomorrow"
        case .thisWeek:     return "This Week"
        case .later:        return "Later"
        case .recentlyDone: return "Recently Done"
        }
    }

    /// Default render order. Sections with zero items are hidden by callers
    /// per FR-HOME-008.
    static let displayOrder: [TimeBucket] =
        [.overdue, .today, .tomorrow, .thisWeek, .later, .recentlyDone]
}

/// Pure classifier — given a reminder and the user's current time/zone,
/// returns which bucket it belongs to. Returns nil for tombstoned reminders
/// and for completed reminders whose `completedAt` is older than 7 days.
enum ReminderBucketing {

    /// Recently Done section only shows the last week of completions.
    static let recentlyDoneWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Per FR-HOME-009: Recently Done caps at 10 entries.
    static let recentlyDoneCap = 10

    static func bucket(
        for reminder: Reminder,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimeBucket? {
        if reminder.pendingDelete { return nil }

        if reminder.completed {
            guard let completedAt = reminder.completedAt else { return nil }
            let age = now.timeIntervalSince(completedAt)
            return age >= 0 && age <= recentlyDoneWindow ? .recentlyDone : nil
        }

        let today = calendar.startOfDay(for: now)
        let triggerDay = calendar.startOfDay(for: reminder.triggerAt)

        if triggerDay < today { return .overdue }
        if triggerDay == today { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           triggerDay == tomorrow {
            return .tomorrow
        }

        // "This week" = today through the end-of-week marker. Foundation's
        // Calendar resolves week boundaries using the user's locale so
        // Mon-start vs Sun-start is handled correctly.
        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now),
           triggerDay < weekInterval.end {
            return .thisWeek
        }
        return .later
    }

    /// Group all reminders by ``TimeBucket``. Null-bucketed entries are
    /// dropped. Within a bucket, items are sorted: Recently Done by
    /// `completedAt` desc, all others by `triggerAt` asc.
    static func groupByBucket(
        _ reminders: [Reminder],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimeBucket: [Reminder]] {
        var grouped: [TimeBucket: [Reminder]] = [:]
        for reminder in reminders {
            guard let b = bucket(for: reminder, now: now, calendar: calendar) else { continue }
            grouped[b, default: []].append(reminder)
        }
        for (bucket, list) in grouped {
            switch bucket {
            case .recentlyDone:
                grouped[bucket] = list
                    .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                    .prefix(recentlyDoneCap)
                    .map { $0 }
            default:
                grouped[bucket] = list.sorted { $0.triggerAt < $1.triggerAt }
            }
        }
        return grouped
    }

    /// Returns the start (Mon 00:00 in locale) and end (Sun 23:59) of the
    /// user's current ISO week, used for weekly stat aggregations.
    static func weekBounds(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: now, duration: 7 * 24 * 60 * 60)
        // dateInterval.end is the start of the next week — back up one
        // millisecond so a strict `<= end` comparison matches the intent.
        let end = interval.end.addingTimeInterval(-0.001)
        return (interval.start, end)
    }
}
