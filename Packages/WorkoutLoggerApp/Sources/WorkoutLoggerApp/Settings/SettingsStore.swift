import WorkoutLoggerCore

/// The slice of preference persistence the settings and onboarding models
/// need: the default kg/lb unit, whether first-run priming has been shown,
/// whether completed workouts are written to Apple Health, and the two
/// privacy opt-ins (anonymous analytics, failed-utterance review) — all
/// defaulting to off. Backed by `UserDefaults` in the app; an in-memory
/// fake in tests.
public protocol SettingsStore: AnyObject {
    var defaultUnit: MassUnit { get set }
    var hasCompletedOnboarding: Bool { get set }
    var syncsToAppleHealth: Bool { get set }
    var analyticsEnabled: Bool { get set }
    var recognitionReviewEnabled: Bool { get set }
}
