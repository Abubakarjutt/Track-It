import Foundation
import Observation
import WorkoutLoggerCore

/// Owns the one-way write of a completed Workout to Apple Health. No-ops
/// unless the opt-in flag is on and authorization is granted, so the core
/// logging loop never waits on or blocks on a Health write. A rough
/// active-energy figure rides along with each workout (see
/// `estimatedActiveEnergyKilocalories`).
///
/// Dedupe is persistent, via `SyncedWorkoutStore` keyed on `Workout.startedAt`:
/// a workout already in Health is not posted again, even after a relaunch.
@MainActor
@Observable
public final class HealthKitSyncModel {
    @ObservationIgnored private let store: HealthKitWorkoutStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let syncedStore: SyncedWorkoutStore

    public private(set) var status: HealthKitSyncStatus

     /// Mirrors `settings.syncsToAppleHealth` so a view re-renders on toggle.
    public private(set) var isEnabled: Bool

    public init(
        store: HealthKitWorkoutStore,
        settings: SettingsStore,
        syncedStore: SyncedWorkoutStore = InMemorySyncedWorkoutStore()
    ) {
        self.store = store
        self.settings = settings
        self.syncedStore = syncedStore
        self.status = store.status
        self.isEnabled = settings.syncsToAppleHealth
     }

    /// Whether a write would happen right now: opted in and authorized.
    public var canSync: Bool { isEnabled && status == .authorized }

     /// Write a just-completed Workout, unless it is already in Health. Silent
     /// unless `canSync`.
    public func workoutEnded(_ workout: Workout) async {
        guard canSync else { return }
        guard !syncedStore.isSynced(startedAt: workout.startedAt) else { return }
        store.write(workout, activeEnergyKilocalories: estimatedActiveEnergyKilocalories(for: workout))
        syncedStore.markSynced(startedAt: workout.startedAt)
     }

     /// Flip the opt-in flag. Enabling requests HealthKit authorization and
     /// reflects the result; disabling stops all further writes immediately
     /// without touching what is already in Health.
    public func setEnabled(_ enabled: Bool) async {
        settings.syncsToAppleHealth = enabled
        isEnabled = enabled
        if enabled {
            await store.request()
            refreshStatus()
         }
     }

     /// Re-read the store's authorization — call on Settings `.onAppear` and
     /// when the app returns to the foreground, since the user can change it in
     /// the Health app or iOS Settings and come back.
    public func refreshStatus() {
        status = store.status
     }
}
