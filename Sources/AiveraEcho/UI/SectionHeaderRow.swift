import SwiftUI

/// Header above each time-grouped reminder section (FR-HOME-007).
///
///   [⚠]  Overdue (2)
///   [📅] Today (3)
///   [☀]  Tomorrow (1)
///   [📆] This Week (4)
///   [⏰] Later (2)
///   [↶]  Recently Done (7)
struct SectionHeaderRow: View {
    let bucket: TimeBucket
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(for: bucket))
                .foregroundStyle(Self.tint(for: bucket))
            Text("\(bucket.title) (\(count))")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(bucket.title), \(count) items")
    }

    private static func symbol(for bucket: TimeBucket) -> String {
        switch bucket {
        case .overdue:      return "exclamationmark.circle.fill"
        case .today:        return "calendar"
        case .tomorrow:     return "sun.max.fill"
        case .thisWeek:     return "calendar.badge.clock"
        case .later:        return "clock.fill"
        case .recentlyDone: return "checkmark.circle"
        }
    }

    private static func tint(for bucket: TimeBucket) -> Color {
        switch bucket {
        case .overdue:      return .red
        case .recentlyDone: return .secondary
        default:            return .echoAccent
        }
    }
}
