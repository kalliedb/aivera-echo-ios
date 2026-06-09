import Foundation

/// Stats and per-bucket reminder groupings that drive the new Home screen
/// (FR-HOME-001 through FR-HOME-014). All values derived from the existing
/// `reminders` table by ``HomeStatsCalculator`` — no new persistence.
///
/// Mirrors `solutions.aivera.echo.home.HomeStats` on Android so the two
/// platforms produce identical numbers from identical task lists.
struct HomeStats: Equatable {

    /// Consecutive days, ending today (or yesterday if today's not done yet),
    /// with at least one completion.
    let currentStreak: Int

    /// Reminders where `completedAt` falls in the current ISO week
    /// (Mon 00:00 → Sun 23:59).
    let completedThisWeek: Int

    /// Active (not-completed, not-tombstoned) location reminders. Drives the
    /// FR-HOME-012 places stat card.
    let activeLocationReminders: Int

    /// Fraction in 0.0–1.0 of reminders due this week that have been
    /// completed. Used by FR-HOME-012 as a percentage. Defined as
    /// `completedThisWeek / max(triggeredThisWeek, 1)` to avoid divide-by-zero
    /// when no reminders are due in the current week.
    let weeklyCompletionRate: Double

    /// Lifetime completions — gate for FR-HOME-013 (hide stats strip when < 3).
    let lifetimeCompleted: Int

    /// Reminders bucketed by ``TimeBucket``. Drives FR-HOME-006/007/008.
    let buckets: [TimeBucket: [Reminder]]

    /// FR-HOME-013: hide the stats strip for users with fewer than 3 lifetime
    /// completions (avoid showing a wall of zeros during onboarding).
    var showStatsStrip: Bool { lifetimeCompleted >= 3 }

    /// FR-HOME-014: completely empty state — no reminders at all.
    var isEmpty: Bool { buckets.values.allSatisfy { $0.isEmpty } }

    func count(_ bucket: TimeBucket) -> Int { buckets[bucket]?.count ?? 0 }

    static let empty = HomeStats(
        currentStreak: 0,
        completedThisWeek: 0,
        activeLocationReminders: 0,
        weeklyCompletionRate: 0,
        lifetimeCompleted: 0,
        buckets: [:]
    )
}
