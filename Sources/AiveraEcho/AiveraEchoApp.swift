import SwiftUI

@main
struct AiveraEchoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .tint(.echoAccent)
                // Long-lived services exposed app-wide.
                .environmentObject(appDelegate.repository)
                .environmentObject(appDelegate.audioPlayer)
                .environmentObject(appDelegate.locationManager)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.syncEngine)
                .onChange(of: scenePhase) { newPhase in
                    // Sync whenever the app comes to the foreground. Cheap if
                    // there's nothing dirty (skips push, pulls empty result).
                    // (Two-argument form is iOS 17+; we target iOS 16.)
                    if newPhase == .active {
                        Task { await appDelegate.syncEngine.syncNow() }
                    }
                }
        }
    }
}
