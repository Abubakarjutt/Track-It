import Foundation
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("HealthKit sync")
struct HealthKitSyncTests {

    private func workout(minutes: Double, ended: Bool = true) -> Workout {
        Workout(
            entries: [],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: ended ? Date(timeIntervalSince1970: minutes * 60) : nil
        )
    }

    // MARK: - Active-energy estimate

    @Test("the active-energy estimate is a rough kcal figure from the workout's duration")
    func energyFromDuration() {
        #expect(estimatedActiveEnergyKilocalories(for: workout(minutes: 40)) == 240)   // 40 * 6.0
        #expect(estimatedActiveEnergyKilocalories(for: workout(minutes: 0)) == 0)
    }

    @Test("a workout that never ended has a zero energy estimate")
    func energyWithoutEnd() {
        #expect(estimatedActiveEnergyKilocalories(for: workout(minutes: 40, ended: false)) == 0)
    }

    // MARK: - HealthKitSyncModel

    @MainActor
    private func makeModel(
        storeStatus: HealthKitSyncStatus = .authorized,
        statusAfterRequest: HealthKitSyncStatus = .authorized,
        enabled: Bool = true
    ) -> (HealthKitSyncModel, FakeHealthKitWorkoutStore, InMemorySettingsStore) {
        let store = FakeHealthKitWorkoutStore(status: storeStatus, statusAfterRequest: statusAfterRequest)
        let settings = InMemorySettingsStore()
        settings.syncsToAppleHealth = enabled
        return (HealthKitSyncModel(store: store, settings: settings), store, settings)
    }

    @Test("a completed workout is written once when sync is on and authorized")
    @MainActor
    func writesWhenEnabledAndAuthorized() async {
        let (model, store, _) = makeModel()

        await model.workoutEnded(workout(minutes: 40))

        #expect(store.saved.count == 1)
        #expect(store.saved.first?.workout == workout(minutes: 40))
        #expect((store.saved.first?.activeEnergyKilocalories ?? 0) > 0)
    }

    @Test("nothing is written when sync is switched off")
    @MainActor
    func silentWhenDisabled() async {
        let (model, store, _) = makeModel(enabled: false)
        await model.workoutEnded(workout(minutes: 40))
        #expect(store.saved.isEmpty)
    }

    @Test("nothing is written when HealthKit authorization is not granted")
    @MainActor
    func silentWhenNotAuthorized() async {
        let (model, store, _) = makeModel(storeStatus: .denied)
        await model.workoutEnded(workout(minutes: 40))
        #expect(store.saved.isEmpty)
    }

    @Test("the same workout end firing twice in a session writes only once")
    @MainActor
    func dedupesWithinSession() async {
        let (model, store, _) = makeModel()
        await model.workoutEnded(workout(minutes: 40))
        await model.workoutEnded(workout(minutes: 40))
        #expect(store.saved.count == 1)
    }

    @Test("turning sync on requests authorization and reflects the result")
    @MainActor
    func enablingRequestsAuthorization() async {
        let (model, store, settings) = makeModel(
            storeStatus: .notDetermined, statusAfterRequest: .authorized, enabled: false
        )
        #expect(model.status == .notDetermined)
        #expect(model.isEnabled == false)

        await model.setEnabled(true)

        #expect(store.authorizationRequests == 1)
        #expect(settings.syncsToAppleHealth)
        #expect(model.status == .authorized)
        #expect(model.isEnabled)
    }

    @Test("refreshStatus re-reads the store after a permission change in the Health app")
    @MainActor
    func refreshStatusRereads() {
        let (model, store, _) = makeModel(storeStatus: .authorized)
        store.set(.denied)
        model.refreshStatus()
        #expect(model.status == .denied)
    }
}
