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

    @Test("a workout in the persistent synced store is not re-written by a fresh model (relaunch)")
    @MainActor
    func persistentDedupeAcrossRelaunch() async {
        let store = FakeHealthKitWorkoutStore(status: .authorized)
        let settings = InMemorySettingsStore()
        settings.syncsToAppleHealth = true
        let synced = InMemorySyncedWorkoutStore()

        let first = HealthKitSyncModel(store: store, settings: settings, syncedStore: synced)
        await first.workoutEnded(workout(minutes: 40))
        #expect(store.saved.count == 1)
        #expect(synced.isSynced(startedAt: Date(timeIntervalSince1970: 0)))

        // relaunch: a brand-new model over the same persistent synced store
        let second = HealthKitSyncModel(store: store, settings: settings, syncedStore: synced)
        await second.workoutEnded(workout(minutes: 40))
        #expect(store.saved.count == 1)   // still just the one write
    }

    @Test("a failed Health write is not marked synced, so the next end retries it")
    @MainActor
    func failedWriteIsNotMarkedSynced() async {
        struct Boom: Error {}
        let store = FakeHealthKitWorkoutStore(status: .authorized)
        store.nextWriteError = Boom()
        let settings = InMemorySettingsStore()
        settings.syncsToAppleHealth = true
        let synced = InMemorySyncedWorkoutStore()
        let model = HealthKitSyncModel(store: store, settings: settings, syncedStore: synced)

        await model.workoutEnded(workout(minutes: 40))
        #expect(synced.isSynced(startedAt: Date(timeIntervalSince1970: 0)) == false)
        #expect(store.saved.isEmpty)

        store.nextWriteError = nil          // the transient failure clears
        await model.workoutEnded(workout(minutes: 40))
        #expect(store.saved.count == 1)     // retried and landed
        #expect(synced.isSynced(startedAt: Date(timeIntervalSince1970: 0)))
    }

    @Test("editing a workout that is already in Health re-syncs it with the new duration")
    @MainActor
    func editedSyncedWorkoutResyncs() async {
        let (model, store, _) = makeModel()

        await model.workoutEnded(workout(minutes: 40))
        #expect(store.saved.count == 1)
        #expect(store.saved.first?.activeEnergyKilocalories == 240)   // 40 * 6.0

        await model.workoutEdited(workout(minutes: 60))

        #expect(store.saved.count == 2)
        #expect(store.saved.last?.activeEnergyKilocalories == 360)     // 60 * 6.0
    }

    @Test("editing a workout that was never synced does nothing")
    @MainActor
    func editedUnsyncedWorkoutIsNoOp() async {
        let (model, store, _) = makeModel()

        await model.workoutEdited(workout(minutes: 60))

        #expect(store.saved.isEmpty)
    }

    @Test("forgetSyncedWorkouts clears the dedupe ledger so ended workouts write again")
    @MainActor
    func forgetSyncedWorkoutsResetsLedger() async {
        let store = FakeHealthKitWorkoutStore(status: .authorized)
        let settings = InMemorySettingsStore()
        settings.syncsToAppleHealth = true
        let synced = InMemorySyncedWorkoutStore()
        let model = HealthKitSyncModel(store: store, settings: settings, syncedStore: synced)

        await model.workoutEnded(workout(minutes: 40))
        #expect(synced.isSynced(startedAt: Date(timeIntervalSince1970: 0)))

        model.forgetSyncedWorkouts()

        #expect(synced.isSynced(startedAt: Date(timeIntervalSince1970: 0)) == false)
        await model.workoutEnded(workout(minutes: 40))
        #expect(store.saved.count == 2)   // wrote again after the ledger was cleared
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
