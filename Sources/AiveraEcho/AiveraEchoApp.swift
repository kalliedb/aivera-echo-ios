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
                .environmentObject(appDelegate.entitlementStore)
                .onChange(of: scenePhase) { newPhase in
                    // Sync + refresh entitlement when the app comes to the foreground.
                    // Both are cheap when there's nothing to do.
                    // (Two-argument form is iOS 17+; we target iOS 16.)
                    if newPhase == .active {
                        Task {
                            await appDelegate.syncEngine.syncNow()
                            await appDelegate.entitlementStore.refresh()
                        }
                    }
                }
        }
    }
}
