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

    public init(settingsStore: SettingsStore, speechAuthorization: SpeechAuthorization) {
        self.settingsStore = settingsStore
        self.speechAuthorization = speechAuthorization
    }

    public var shouldShowOnboarding: Bool { !settingsStore.hasCompletedOnboarding }

    /// Fire the system speech / microphone prompts, then record that priming
    /// is done — regardless of what the user chose.
    public func completeOnboarding() async {
        await speechAuthorization.request()
        settingsStore.hasCompletedOnboarding = true
    }
}
