import Combine
import Foundation
import SwiftUI

/// UserDefaults-backed @MainActor store. Any mutation persists immediately;
/// SwiftUI views observe via @EnvironmentObject and re-render on change.
@MainActor
final class SettingsStore: ObservableObject {

    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let storageKey = "echo.settings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// SwiftUI binding into a single field. Used by SettingsView pickers/toggles.
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    /// Resolve the user's theme choice into a SwiftUI ColorScheme.
    var preferredColorScheme: ColorScheme? {
        switch settings.theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
