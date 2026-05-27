import SwiftUI

@main
struct AiveraEchoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
                .tint(.echoAccent)
                // Lift the long-lived services into the environment so any
                // view down the tree can pull them with @EnvironmentObject.
                .environmentObject(appDelegate.repository)
                .environmentObject(appDelegate.audioPlayer)
                .environmentObject(appDelegate.locationManager)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.syncEngine)
        }
    }
}
