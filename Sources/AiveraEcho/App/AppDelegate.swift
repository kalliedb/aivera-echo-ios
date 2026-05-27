import UIKit
import UserNotifications

/// SwiftUI bridges to UIKit lifecycle via `@UIApplicationDelegateAdaptor`. This
/// is where we own the long-lived singletons (DB, repo, scheduler, audio player)
/// and where we receive notification delegate callbacks — the only place the
/// system can talk back to us when the app isn't on screen.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    let database:     AppDatabase
    let repository:   ReminderRepository
    let audioPlayer:  AudioPlayer
    let scheduler:    NotificationScheduler

    override init() {
        // Database: prefer the file-backed DB. If the disk is unwritable for
        // any reason, fall back to an in-memory DB so the app still launches.
        let db: AppDatabase
        do {
            db = try AppDatabase.makeShared()
        } catch {
            print("AppDelegate: file DB failed, falling back to in-memory: \(error)")
            // swiftlint:disable:next force_try
            db = try! AppDatabase.makeEphemeral()
        }
        let scheduler = NotificationScheduler()
        self.database     = db
        self.scheduler    = scheduler
        self.audioPlayer  = AudioPlayer()
        self.repository   = ReminderRepository(database: db, scheduler: scheduler)
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        scheduler.registerCategories()
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is in the foreground (otherwise
    /// the system suppresses them silently — surprising UX).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handle taps on notification actions (Done / Snooze / Play / default tap).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let reminderId = response.notification.request.identifier
        let actionId   = response.actionIdentifier
        let userInfo   = response.notification.request.content.userInfo

        Task { @MainActor in
            switch actionId {
            case NotificationScheduler.Action.done:
                await handleDone(reminderId: reminderId)
            case NotificationScheduler.Action.snooze15:
                await handleSnooze(reminderId: reminderId, minutes: 15)
            case NotificationScheduler.Action.play:
                let path = userInfo["audioPath"] as? String
                audioPlayer.play(path: path)
            case UNNotificationDefaultActionIdentifier:
                // User tapped the body of the notification. Nothing to do
                // yet — could navigate to a detail view in a later milestone.
                break
            default:
                break
            }
            completionHandler()
        }
    }

    // MARK: - Action handlers

    private func handleDone(reminderId: String) async {
        do {
            guard let reminder = try await repository.findById(reminderId) else { return }
            if !reminder.completed {
                try await repository.toggleComplete(reminder)
            }
        } catch {
            print("Done handler failed: \(error)")
        }
    }

    private func handleSnooze(reminderId: String, minutes: Int) async {
        do {
            guard let reminder = try await repository.findById(reminderId) else { return }
            try await repository.snooze(reminder, minutes: minutes)
        } catch {
            print("Snooze handler failed: \(error)")
        }
    }
}
