import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("Settings fakes")
@MainActor
struct SettingsFakesTests {

     @Test("InMemorySettingsStore round-trips its values")
    func settingsStoreRoundTrip() {
        let store = InMemorySettingsStore()
        #expect(store.defaultUnit == .kilograms)
        #expect(store.hasCompletedOnboarding == false)
        #expect(store.syncsToAppleHealth == false)
        #expect(store.appearance == .dark)

        store.defaultUnit = .pounds
        store.hasCompletedOnboarding = true
        store.syncsToAppleHealth = true
        store.appearance = .light

        #expect(store.defaultUnit == .pounds)
        #expect(store.hasCompletedOnboarding == true)
        #expect(store.syncsToAppleHealth == true)
        #expect(store.appearance == .light)
      }

    @Test("FakeSpeechAuthorization reports its status and transitions on request()")
    func speechAuthFake() async {
        let auth = FakeSpeechAuthorization(status: .notDetermined, resultAfterRequest: .denied)
        #expect(auth.status == .notDetermined)
        #expect(auth.requestCount == 0)

        await auth.request()

        #expect(auth.status == .denied)
        #expect(auth.requestCount == 1)
    }
}
