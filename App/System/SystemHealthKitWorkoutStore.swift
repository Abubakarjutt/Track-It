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

    /// The types trackit shares: a workout and its active-energy total.
    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    var status: HealthKitSyncStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .notDetermined:
            return .notDetermined
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        @unknown default:
            return .notDetermined
        }
     }

    func request() async {
        try? await store.requestAuthorization(toShare: shareTypes, read: [])
     }

    func write(_ workout: Workout, activeEnergyKilocalories: Double) async {
        lastWriteError = nil
        let started = workout.startedAt
        guard let ended = workout.endedAt else { return }

        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: activeEnergyKilocalories)
        // `HKWorkout.init` is soft-deprecated in favour of `HKWorkoutBuilder`; the
        // builder is a multi-call session and this adapter is a single write
        // seam, so the classic initializer stays until a builder migration is
        // scoped on its own.
        let sample = HKWorkout(
            activityType: .functionalStrengthTraining,
            start: started,
            end: ended,
            duration: ended.timeIntervalSince(started),
            totalEnergyBurned: energy,
            totalDistance: nil,
            metadata: nil
        )

        lastWriteError = await withCheckedContinuation { continuation in
            store.save(sample) { _, error in continuation.resume(returning: error) }
        }
     }
}
