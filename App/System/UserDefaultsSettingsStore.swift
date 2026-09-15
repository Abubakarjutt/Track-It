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
        static let syncsToHealth = "syncsToAppleHealth"
        static let analytics = "analyticsEnabled"
        static let recognitionReview = "recognitionReviewEnabled"
        static let appearance = "appearance"
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

    var syncsToAppleHealth: Bool {
        get { defaults.bool(forKey: Key.syncsToHealth) }
        set { defaults.set(newValue, forKey: Key.syncsToHealth) }
       }

    var analyticsEnabled: Bool {
        get { defaults.bool(forKey: Key.analytics) }
        set { defaults.set(newValue, forKey: Key.analytics) }
       }

    var recognitionReviewEnabled: Bool {
        get { defaults.bool(forKey: Key.recognitionReview) }
        set { defaults.set(newValue, forKey: Key.recognitionReview) }
       }

    /// Stored as a short string; the absent key (first launch, or a value
    /// written by a future case this build doesn't know) reads as `.dark` —
    /// preserving the app's pre-light-mode look until a user opts in.
    var appearance: Appearance {
        get {
            switch defaults.string(forKey: Key.appearance) {
            case "system": return .system
            case "light": return .light
            default: return .dark
            }
        }
        set {
            let raw: String
            switch newValue {
            case .system: raw = "system"
            case .light: raw = "light"
            case .dark: raw = "dark"
            }
            defaults.set(raw, forKey: Key.appearance)
        }
    }
}
