import Foundation
import HealthKit
import WorkoutLoggerCore
import WorkoutLoggerApp

/// `HealthKitWorkoutStore` over `HKHealthStore`. A thin adapter: it flattens
/// `HKAuthorizationStatus` into the few states the UI distinguishes, requests
/// the one write type trackit uses, and writes one `HKWorkout`
/// (traditional strength-training) per completed Workout with its rough
/// active-energy figure. One-way, write-once, no reads. Not compiled in this
/// environment, so its shape is consistency-checked, not type-checked.
@MainActor
final class SystemHealthKitWorkoutStore: HealthKitWorkoutStore {
    private let store = HKHealthStore()
    public private(set) var lastWriteError: Error?

     /// The two writable types trackit requests: a strength-training workout and
     /// its active-energy figure.
     private var writeTypes: [HKObjectType] {
        [HKWorkoutType(.traditionalStrengthTraining, activityType: .functionalStrengthTraining),
         HKQuantityType(.appleActiveEnergyBurned)]
     }

    var status: HealthKitSyncStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch store.authorizationStatus(forWrite: writeTypes) {
        case .notDetermined:
            return .notDetermined
        case .sharingAuthorized, .authorizeIfNeeded:
            return .authorized
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .notDetermined
        }
     }

    func request() async {
        await withCheckedContinuation { cont in
            store.requestAuthorization(toWrite: writeTypes) { _ in cont.resume() }
        }
     }

    func write(_ workout: Workout, activeEnergyKilocalories: Double) {
        guard let started = workout.startedAt, let ended = workout.endedAt else { return }

        let energy = HKQuantity(
            unit: .kilocalorie(),
            doubleValue: activeEnergyKilocalories
        )
        let workoutType: HKWorkoutType = .traditionalStrengthTraining(
            activityType: .functionalStrengthTraining
        )
        let sample = HKWorkout(
            activityType: .functionalStrengthTraining,
            start: started,
            end: ended,
            quantitySummary: energy,
            metadata: nil,
            type: workoutType
        )

        do {
            try store.save(sample)
            lastWriteError = nil
        } catch {
            lastWriteError = error
        }
     }
}
