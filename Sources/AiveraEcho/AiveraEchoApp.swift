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
                .onChange(of: scenePhase) { _, newPhase in
                    // Sync + refresh entitlement when the app comes to the foreground.
                    // Both are cheap when there's nothing to do.
                    // Two-argument closure is required since the iOS 16
                    // single-arg form was deprecated in iOS 17. Our minimum
                    // deployment target is iOS 17, so no @available guard needed.
                    if newPhase == .active {
                        // FR-HOME-020 — recompute Daily Hero greeting + time
                        // bucket boundaries against the current wall clock,
                        // so an overnight idle doesn't leave us stuck on the
                        // previous day's groupings.
                        appDelegate.repository.refreshStats()
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
