import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter` for the reminder lifecycle. The notification
/// identifier IS the reminder.id, so schedule/cancel are idempotent and keyed.
///
/// Time-based reminders use `UNCalendarNotificationTrigger`, which fires even
/// when the app is force-quit — no `BGTaskScheduler` needed for that case.
/// Place-based reminders (M3.1) will use `CLCircularRegion` triggers separately.
@MainActor
final class NotificationScheduler {

    // Notification category + action identifiers — kept as plain strings so
    // the AppDelegate can match without importing this class.
    enum Category {
        static let reminder = "echo.reminder"
    }
    enum Action {
        static let done       = "echo.action.done"
        static let snooze15   = "echo.action.snooze15"
        static let play       = "echo.action.play"  // wired in M2.5
    }

    /// Register the action categories. Call once at app launch.
    func registerCategories() {
        let done = UNNotificationAction(
            identifier: Action.done,
            title: "Done",
            options: []
        )
        let snooze15 = UNNotificationAction(
            identifier: Action.snooze15,
            title: "Snooze 15m",
            options: []
        )
        let play = UNNotificationAction(
            identifier: Action.play,
            title: "Play",
            options: [.foreground]   // needs app foreground to start AVAudioPlayer
        )

        let category = UNNotificationCategory(
            identifier: Category.reminder,
            actions: [play, snooze15, done],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Request authorisation if the user hasn't been prompted yet. Best-effort:
    /// if they decline, schedule() silently no-ops on actual add().
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("Notification auth failed: \(error)")
                return false
            }
        case .denied:
            return false
        case .authorized, .provisional, .ephemeral:
            return true
        @unknown default:
            return false
        }
    }

    /// Schedule (or reschedule) a notification for `reminder`. Cancels any
    /// existing notification with the same identifier first — so update/snooze
    /// flows just call this and don't worry about stale notifications firing.
    func schedule(_ reminder: Reminder) async {
        // Cancel any previous request for this reminder first (idempotent).
        cancel(reminderId: reminder.id)

        // Only schedule for time-based reminders that haven't fired yet and
        // aren't already completed.
        guard !reminder.completed,
              reminder.triggerType == .time,
              reminder.triggerAt > Date() else { return }

        // Make sure permission is granted (contextual prompt on first save).
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body  = reminder.text.isEmpty ? "Voice reminder" : reminder.text
        content.sound = .default
        content.categoryIdentifier = Category.reminder
        content.userInfo = [
            "reminderId": reminder.id,
            "audioPath":  reminder.audioPath ?? "",
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.triggerAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: reminder.id,
            content:    content,
            trigger:    trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification for \(reminder.id): \(error)")
        }
    }

    /// Fire a notification right now (used by GeofenceManager on region enter).
    /// Identifier includes a timestamp so iOS doesn't dedupe against any
    /// scheduled future delivery for the same reminder.
    func fireImmediate(for reminder: Reminder) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        let bodyBase  = reminder.text.isEmpty ? "Voice reminder" : reminder.text
        if let place = reminder.placeLabel, !place.isEmpty {
            content.body = "\(bodyBase) — \(place)"
        } else {
            content.body = bodyBase
        }
        content.sound = .default
        content.categoryIdentifier = Category.reminder
        content.userInfo = [
            "reminderId": reminder.id,
            "audioPath":  reminder.audioPath ?? "",
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(reminder.id)-fired-\(Int(Date().timeIntervalSince1970))",
            content:    content,
            trigger:    trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("fireImmediate failed for \(reminder.id): \(error)")
        }
    }

    /// Remove pending + delivered notifications for a single reminder.
    func cancel(reminderId: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderId])
        center.removeDeliveredNotifications(withIdentifiers: [reminderId])
    }

    /// Wipe everything — used by Settings → Delete my data (M3.4).
    func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
