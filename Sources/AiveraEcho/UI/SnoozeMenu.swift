import SwiftUI

/// Menu button shown on each active time-based reminder row. Offers four
/// snooze options identical to the Android dropdown. "Custom…" surfaces a
/// `.sheet`-driven date picker controlled by the parent view (`HomeView`).
struct SnoozeMenu: View {
    let onSnooze: (Int) -> Void
    let onSnoozeCustom: () -> Void

    var body: some View {
        Menu {
            Button { onSnooze(5) }      label: { Label("Snooze 5 minutes",  systemImage: "5.circle") }
            Button { onSnooze(15) }     label: { Label("Snooze 15 minutes", systemImage: "15.circle") }
            Button { onSnooze(60) }     label: { Label("Snooze 1 hour",     systemImage: "clock") }
            Divider()
            Button { onSnoozeCustom() } label: { Label("Custom…",           systemImage: "calendar") }
        } label: {
            Image(systemName: "alarm")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)   // 44pt min hit target
        }
        .accessibilityLabel("Snooze options")
    }
}
