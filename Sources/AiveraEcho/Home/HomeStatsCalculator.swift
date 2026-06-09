import Foundation

/// Pure compute layer that turns a `[Reminder]` snapshot into ``HomeStats``.
///
/// Stateless and side-effect free — every input determines the output, so
/// trivial to unit-test once iOS test target exists.
///
/// Called reactively by the iOS HomeView whenever the GRDB ValueObservation
/// emits a fresh reminder list, plus on `.scenePhase == .active` to handle
/// date-roll-over while the app sits idle (FR-HOME-020).
enum HomeStatsCalculator {

    /// - Parameters:
    ///   - reminders: full snapshot (active + completed, excluding tombstones
    ///     because ReminderRepository's observation already filters those).
    ///   - now: reference instant — usually `Date()`, but injected so future
    ///     tests can pin time.
    ///   - calendar: the user's calendar; drives day + week boundaries.
    static func compute(
        reminders: [Reminder],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HomeStats {
        let today = calendar.startOfDay(for: now)
        let weekRange = ReminderBucketing.weekBounds(now: now, calendar: calendar)

        let active = reminders.filter { !$0.completed && !$0.pendingDelete }
        let completed = reminders.filter { $0.completed && !$0.pendingDelete }

        let completedThisWeek = completed.filter { r in
            guard let at = r.completedAt else { return false }
            return at >= weekRange.start && at <= weekRange.end
        }.count

        let triggeredThisWeek = reminders.filter { r in
            !r.pendingDelete &&
                r.triggerAt >= weekRange.start &&
                r.triggerAt <= weekRange.end
        }.count

        let weeklyRate: Double = triggeredThisWeek > 0
            ? Double(completedThisWeek) / Double(triggeredThisWeek)
            : 0.0

        let activeLocations = active.filter { $0.triggerType == .location }.count
        let buckets = ReminderBucketing.groupByBucket(reminders, now: now, calendar: calendar)

        return HomeStats(
            currentStreak: currentStreak(completed: completed, today: today, calendar: calendar),
            completedThisWeek: completedThisWeek,
            activeLocationReminders: activeLocations,
            weeklyCompletionRate: weeklyRate,
            lifetimeCompleted: completed.count,
            buckets: buckets
        )
    }

    /// Consecutive-day streak ending today (or yesterday, with a one-day
    /// grace window so a fresh morning with no completions yet doesn't
    /// break the streak immediately).
    private static func currentStreak(
        completed: [Reminder],
        today: Date,
        calendar: Calendar
    ) -> Int {
        guard !completed.isEmpty else { return 0 }

        // Collect the set of distinct calendar days on which any reminder
        // was completed.
        let completedDays: Set<Date> = Set(
            completed.compactMap { r -> Date? in
                guard let at = r.completedAt else { return nil }
                return calendar.startOfDay(for: at)
            }
        )

        // Grace: if today has no completion but yesterday does, count from
        // yesterday. Otherwise streak = 0.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let start: Date
        if completedDays.contains(today) {
            start = today
        } else if completedDays.contains(yesterday) {
            start = yesterday
        } else {
            return 0
        }

        // Walk back day-by-day until the first missing day.
        var streak = 0
        var day = start
        while completedDays.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}
