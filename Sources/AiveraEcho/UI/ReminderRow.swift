import SwiftUI

struct ReminderRow: View {
    let reminder: Reminder
    let onToggle: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: reminder.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(reminder.completed ? Color.echoAccent : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.text)
                    .font(.body.weight(.medium))
                    .strikethrough(reminder.completed)
                    .foregroundStyle(reminder.completed ? Color.secondary : Color.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if reminder.triggerType == .location {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                        Text(reminder.placeLabel ?? "Place")
                    } else {
                        Text(reminder.triggerAt, format: .dateTime.day().month().hour().minute())
                        if !reminder.completed {
                            Text("·")
                            Text(reminder.triggerAt, style: .relative)
                        }
                    }
                    if reminder.recurrence != .none {
                        Text("·")
                        Text(reminder.recurrence.label)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if reminder.audioPath != nil {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.echoAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play recording")
            }
        }
        .padding(.vertical, 6)
    }
}
