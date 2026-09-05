import WorkoutLoggerCore

/// The slice of preference persistence the settings and onboarding models
/// need: the default kg/lb unit and whether first-run priming has been shown.
/// Backed by `UserDefaults` in the app; an in-memory fake in tests.
public protocol SettingsStore: AnyObject {
    var defaultUnit: MassUnit { get set }
    var hasCompletedOnboarding: Bool { get set }
}
