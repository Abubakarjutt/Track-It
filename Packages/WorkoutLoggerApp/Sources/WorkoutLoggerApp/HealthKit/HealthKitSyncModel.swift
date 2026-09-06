import Foundation
import Observation
import WorkoutLoggerCore

/// Owns the one-way write of a completed Workout to Apple Health. No-ops
/// unless the opt-in flag is on and authorization is granted, so the core
/// logging loop never waits on or blocks on a Health write. A rough
/// active-energy figure rides along with each workout (see
/// `estimatedActiveEnergyKilocalories`); the Health entry is a write-once
/// snapshot and is not rewritten if the workout is later edited.
@MainActor
@Observable
public final class HealthKitSyncModel {
    @ObservationIgnored private let store: HealthKitWorkoutStore
    @ObservationIgnored private let settings: SettingsStore

     /// Workouts written this session, keyed by start time, so a repeated end
     /// (resume / double-end) writes once.
    @ObservationIgnored private var writtenStartTimes = Set<Date>()

    public private(set) var status: HealthKitSyncStatus

     /// Mirrors `settings.syncsToAppleHealth` so a view re-renders on toggle.
    public private(set) var isEnabled: Bool

    public init(store: HealthKitWorkoutStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        self.status = store.status
        self.isEnabled = settings.syncsToAppleHealth
     }

    /// Whether a write would happen right now: opted in and authorized.
    public var canSync: Bool { isEnabled && status == .authorized }

     /// Write a just-completed Workout, once per session. Silent unless
     /// `canSync`.
    public func workoutEnded(_ workout: Workout) async {
        guard canSync else { return }
        guard !writtenStartTimes.contains(workout.startedAt) else { return }
        writtenStartTimes.insert(workout.startedAt)
        store.write(workout, activeEnergyKilocalories: estimatedActiveEnergyKilocalories(for: workout))
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
