import Foundation

/// User-tunable settings. Mirrors Android's `Settings` data class so a single
/// design discussion covers both platforms. Persisted as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    var theme: ThemeMode = .dark
    var audioRetentionDays: Int = 7
    var soundEnabled: Bool = true
    var vibrationEnabled: Bool = true
    var quietHoursEnabled: Bool = false
    var locationEnabled: Bool = false
    var cloudSyncEnabled: Bool = true
    var onboardingCompleted: Bool = false
}

enum ThemeMode: String, Codable, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}
