import SwiftUI

struct ReminderRow: View {
    let reminder: Reminder
    var isPlaying: Bool = false
    let onToggle: () -> Void
    let onPlay: () -> Void
    /// Tap on the text / time area opens the reminder in edit mode.
    /// Explicit buttons (toggle, play, snooze) remain independent.
    var onEdit: (() -> Void)? = nil
    var onSnooze: ((Int) -> Void)? = nil
    var onSnoozeCustom: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: reminder.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(reminder.completed ? Color.echoAccent : Color.secondary)
            }
            .buttonStyle(.plain)

            // The reminder body (text + time/place) is a tap target that opens
            // the edit sheet. Wrapped in Button rather than .onTapGesture so
            // VoiceOver announces it as activatable.
            Button(action: { onEdit?() }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.text)
                        .font(.body.weight(.medium))
                        .strikethrough(reminder.completed)
                        .foregroundStyle(reminder.completed ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(onEdit == nil)
            .accessibilityHint(onEdit == nil ? "" : "Double-tap to edit")

            Spacer(minLength: 0)

            if reminder.audioPath != nil {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.echoAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Stop playback" : "Play recording")
            }

            // Snooze menu — only for active time-based reminders.
            if !reminder.completed,
               reminder.triggerType == .time,
               let onSnooze, let onSnoozeCustom {
                SnoozeMenu(onSnooze: onSnooze, onSnoozeCustom: onSnoozeCustom)
            }
        }
        .padding(.vertical, 6)
    }
}
