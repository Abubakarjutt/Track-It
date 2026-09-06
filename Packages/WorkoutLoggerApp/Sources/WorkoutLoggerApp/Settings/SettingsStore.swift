import WorkoutLoggerCore

/// The slice of preference persistence the settings and onboarding models
/// need: the default kg/lb unit, whether first-run priming has been shown, and
/// whether completed workouts are written to Apple Health. Backed by
/// `UserDefaults` in the app; an in-memory fake in tests.
public protocol SettingsStore: AnyObject {
    var defaultUnit: MassUnit { get set }
    var hasCompletedOnboarding: Bool { get set }
    var syncsToAppleHealth: Bool { get set }
}
