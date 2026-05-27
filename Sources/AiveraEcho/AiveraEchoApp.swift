import SwiftUI

@main
struct AiveraEchoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.echoAccent)
                // Long-lived services exposed app-wide.
                .environmentObject(appDelegate.repository)
                .environmentObject(appDelegate.audioPlayer)
                .environmentObject(appDelegate.locationManager)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.syncEngine)
                .environmentObject(appDelegate.entitlementStore)
                .environmentObject(appDelegate.settingsStore)
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

/// Decides between onboarding (first launch) and HomeView; applies the user's
/// chosen colour scheme. Pulled into its own view so it can subscribe to the
/// settings store via @EnvironmentObject (App body can't do that cleanly).
private struct RootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Group {
            if settingsStore.settings.onboardingCompleted {
                HomeView()
            } else {
                OnboardingView {
                    settingsStore.settings.onboardingCompleted = true
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: settingsStore.settings.onboardingCompleted)
        .preferredColorScheme(settingsStore.preferredColorScheme)
    }
}
