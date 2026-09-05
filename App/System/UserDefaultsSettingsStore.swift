import Foundation
import WorkoutLoggerCore
import WorkoutLoggerApp

/// `SettingsStore` over `UserDefaults.standard`. No logic beyond key access —
/// the unit is stored as a short string so the default (absent key) reads as
/// kilograms.
final class UserDefaultsSettingsStore: SettingsStore {
    private enum Key {
        static let unit = "defaultMassUnit"
        static let onboarded = "hasCompletedOnboarding"
    }
    private let defaults = UserDefaults.standard

    var defaultUnit: MassUnit {
        get { defaults.string(forKey: Key.unit) == "pounds" ? .pounds : .kilograms }
        set { defaults.set(newValue == .pounds ? "pounds" : "kilograms", forKey: Key.unit) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }
}
