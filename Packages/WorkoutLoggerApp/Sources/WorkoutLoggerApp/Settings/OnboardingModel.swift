import Observation

/// Gates the one-screen first-run permission-priming flow. The flag is a
/// one-way latch on "the priming screen was shown and dismissed"; it is not
/// re-derived from live authorization, so a later denial in iOS Settings does
/// not re-trigger onboarding — recovery lives in the Settings Speech section.
@MainActor
@Observable
public final class OnboardingModel {
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let speechAuthorization: SpeechAuthorization

    /// Mirrors `settingsStore.hasCompletedOnboarding`. Held as a tracked
    /// stored property (not computed off the `@ObservationIgnored` store) so
    /// the gate in `RootView` re-renders when `completeOnboarding()` flips it.
    private var completed: Bool

    public init(settingsStore: SettingsStore, speechAuthorization: SpeechAuthorization) {
        self.settingsStore = settingsStore
        self.speechAuthorization = speechAuthorization
        self.completed = settingsStore.hasCompletedOnboarding
    }

    public var shouldShowOnboarding: Bool { !completed }

    /// Fire the system speech / microphone prompts, then record that priming
    /// is done — regardless of what the user chose.
    public func completeOnboarding() async {
        await speechAuthorization.request()
        settingsStore.hasCompletedOnboarding = true
        completed = true
    }
}
