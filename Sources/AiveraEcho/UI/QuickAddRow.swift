import SwiftUI

/// Quick-add chip row (iOS port of Android's QuickAddRow / FR-HOME-016).
///
///   [+ Today]  [+ Tomorrow]  [+ This Week]
///
/// Each chip opens the manual-entry ReviewSheet with `triggerAt` pre-filled
/// to a sensible default for the chosen bucket:
///   Today      → 18:00 today, or now + 1h if 18:00 already passed
///   Tomorrow   → 09:00 tomorrow
///   This Week  → Friday 17:00 (Mon–Thu) or next Monday 09:00 (Fri–Sun)
struct QuickAddRow: View {
    let onQuickAdd: (Date) -> Void

    var body: some View {
        HStack(spacing: 8) {
            chip("+ Today")    { onQuickAdd(Self.targetDate(for: .today)) }
            chip("+ Tomorrow") { onQuickAdd(Self.targetDate(for: .tomorrow)) }
            chip("+ This Week"){ onQuickAdd(Self.targetDate(for: .thisWeek)) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.echoAccent.opacity(0.12))
                )
                .foregroundStyle(Color.echoAccent)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Creates a reminder pre-set for \(label.dropFirst(2))")
    }

    private enum Bucket { case today, tomorrow, thisWeek }

    private static func targetDate(for bucket: Bucket, now: Date = Date(),
                                   calendar: Calendar = .current) -> Date {
        switch bucket {
        case .today:
            // 18:00 today, or now + 1h rounded down to the hour if past 18:00.
            let eighteen = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
                ?? now.addingTimeInterval(3600)
            return eighteen > now ? eighteen : nextHour(after: now, calendar: calendar)
        case .tomorrow:
            let tomorrowMidnight = calendar.date(byAdding: .day, value: 1,
                                                 to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                 of: tomorrowMidnight) ?? tomorrowMidnight
        case .thisWeek:
            let weekday = calendar.component(.weekday, from: now) // 1=Sun, 6=Fri
            if weekday >= 2 && weekday <= 5 {
                // Mon–Thu: next Friday 17:00
                let friday = next(weekday: 6, after: now, calendar: calendar)
                return calendar.date(bySettingHour: 17, minute: 0, second: 0,
                                     of: friday) ?? friday
            } else {
                // Fri–Sun: next Monday 09:00
                let monday = next(weekday: 2, after: now, calendar: calendar)
                return calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                     of: monday) ?? monday
            }
        }
    }

    private static func nextHour(after date: Date, calendar: Calendar) -> Date {
        let nextHourStart = calendar.date(byAdding: .hour, value: 1, to: date) ?? date
        return calendar.date(bySettingHour: calendar.component(.hour, from: nextHourStart),
                             minute: 0, second: 0, of: nextHourStart) ?? nextHourStart
    }

    private static func next(weekday: Int, after date: Date, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        return calendar.nextDate(after: date, matching: components,
                                 matchingPolicy: .nextTime) ?? date
    }
}
