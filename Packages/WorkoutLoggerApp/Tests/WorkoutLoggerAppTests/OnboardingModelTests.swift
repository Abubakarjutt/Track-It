import Testing
@testable import WorkoutLoggerApp

@Suite("OnboardingModel")
@MainActor
struct OnboardingModelTests {

    @Test("shouldShowOnboarding mirrors the persisted flag")
    func mirrorsFlag() {
        let notDone = OnboardingModel(
            settingsStore: InMemorySettingsStore(hasCompletedOnboarding: false),
            speechAuthorization: FakeSpeechAuthorization()
        )
        let done = OnboardingModel(
            settingsStore: InMemorySettingsStore(hasCompletedOnboarding: true),
            speechAuthorization: FakeSpeechAuthorization()
        )
        #expect(notDone.shouldShowOnboarding == true)
        #expect(done.shouldShowOnboarding == false)
    }

    @Test("completeOnboarding requests auth then sets the flag, even on denial")
    func completeOnDenial() async {
        let store = InMemorySettingsStore(hasCompletedOnboarding: false)
        let auth = FakeSpeechAuthorization(status: .notDetermined, resultAfterRequest: .denied)
        let model = OnboardingModel(settingsStore: store, speechAuthorization: auth)

        await model.completeOnboarding()

        #expect(auth.requestCount == 1)
        #expect(store.hasCompletedOnboarding == true)
        #expect(model.shouldShowOnboarding == false)
    }
}
