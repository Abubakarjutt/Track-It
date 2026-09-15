import WorkoutLoggerCore

/// The colour scheme the app should render in outside the HUD. `HUDView` —
/// the glanceable, arms-length, mid-workout screen — always renders dark
/// regardless of this setting; this only reaches every other screen
/// (Onboarding, the resume/discard gate, History, Progress, Settings, and
/// everything reachable from them). See
/// `docs/superpowers/specs/2026-09-11-cluster-7e-light-mode.md` OPEN
/// QUESTION 1's resolution for the exact boundary.
public enum Appearance: Equatable, Sendable, Codable {
    case system
    case light
    case dark
}

/// The slice of preference persistence the settings and onboarding models
/// need: the default kg/lb unit, whether first-run priming has been shown,
/// whether completed workouts are written to Apple Health, the two privacy
/// opt-ins (anonymous analytics, failed-utterance review — defaulting to
/// off), and the non-HUD colour scheme (defaulting to dark, preserving the
/// app's pre-light-mode look). Backed by `UserDefaults` in the app; an
/// in-memory fake in tests.
public protocol SettingsStore: AnyObject {
    var defaultUnit: MassUnit { get set }
    var hasCompletedOnboarding: Bool { get set }
    var syncsToAppleHealth: Bool { get set }
    var analyticsEnabled: Bool { get set }
    var recognitionReviewEnabled: Bool { get set }
    var appearance: Appearance { get set }
}
