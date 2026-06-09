import SwiftUI

/// Top-of-Home greeting block (FR-HOME-001 to 005).
///
///   Good morning
///   Wednesday, 27 May
///
///   3 reminders today · 1 overdue        ← or "Your day is clear ✨"
///
/// Weather chip (FR-HOME-004) and display name in greeting (FR-HOME-005)
/// intentionally deferred — same rationale as on Android:
///   - Weather needs a provider SDK + API key.
///   - Email-derived names look bad ("kalliedb" → "Kalliedb"). Will
///     wire once a real display_name field lives on the user profile.
struct DailyHeroHeader: View {
    let stats: HomeStats
    var displayName: String? = nil
    var now: Date = Date()

    var body: some View {
        let hour = Calendar.current.component(.hour, from: now)
        let greeting = Self.buildGreeting(hour: hour, name: displayName)
        let dateLine = now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let quickStat = Self.buildQuickStat(
            today: stats.count(.today),
            overdue: stats.count(.overdue)
        )

        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(dateLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 6)
            Text(quickStat)
                .font(.body)
                .foregroundStyle(Color.echoAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(greeting). \(dateLine). \(quickStat)")
    }

    /// Time-of-day adaptive greeting.
    static func buildGreeting(hour: Int, name: String?) -> String {
        let tod: String
        switch hour {
        case 4...11:  tod = "Good morning"
        case 12...17: tod = "Good afternoon"
        default:      tod = "Good evening"   // 18-23 and 0-3
        }
        guard let name, !name.isEmpty else { return tod }
        return "\(tod), \(name)"
    }

    /// Per FR-HOME-003:
    ///   both counts == 0          → "Your day is clear ✨"
    ///   only overdue is 0         → "N reminder(s) today"
    ///   only today is 0           → "N overdue reminder(s)"
    ///   both                       → "N reminder(s) today · M overdue"
    static func buildQuickStat(today: Int, overdue: Int) -> String {
        switch (today, overdue) {
        case (0, 0):
            return "Your day is clear ✨"
        case (let t, 0):
            return pluralise(t, "reminder", "reminders") + " today"
        case (0, let o):
            return pluralise(o, "overdue reminder", "overdue reminders")
        case (let t, let o):
            return "\(pluralise(t, "reminder", "reminders")) today · \(o) overdue"
        }
    }

    private static func pluralise(_ n: Int, _ singular: String, _ plural: String) -> String {
        n == 1 ? "1 \(singular)" : "\(n) \(plural)"
    }
}
