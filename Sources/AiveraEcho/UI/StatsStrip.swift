import SwiftUI

/// Horizontally scrollable strip of stat cards (FR-HOME-010 to 013).
///
///   🔥 7 day streak     ✓ 12 this week     📍 3 active places     % 85% rate
///
/// Hidden when `stats.showStatsStrip == false` (lifetime completions < 3 —
/// per FR-HOME-013, avoids a wall-of-zeros during onboarding).
struct StatsStrip: View {
    let stats: HomeStats

    var body: some View {
        if !stats.showStatsStrip {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    StatCard(
                        symbol: "flame.fill",
                        accent: .orange,
                        value: "\(stats.currentStreak)",
                        label: "day streak"
                    )
                    StatCard(
                        symbol: "checkmark.circle.fill",
                        accent: .echoAccent,
                        value: "\(stats.completedThisWeek)",
                        label: "done this week"
                    )
                    if stats.activeLocationReminders > 0 {
                        StatCard(
                            symbol: "mappin.circle.fill",
                            accent: .blue,
                            value: "\(stats.activeLocationReminders)",
                            label: stats.activeLocationReminders == 1 ? "active place" : "active places"
                        )
                    }
                    StatCard(
                        symbol: "percent",
                        accent: .purple,
                        value: "\(Int((stats.weeklyCompletionRate * 100).rounded()))%",
                        label: "weekly rate"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct StatCard: View {
    let symbol: String
    let accent: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .font(.body)
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 132, height: 82, alignment: .topLeading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
