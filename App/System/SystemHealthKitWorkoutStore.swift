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
        // scoped on its own. The external-UUID stamp is trackit's handle on the
        // sample, so a later edit can find and replace exactly this workout.
        let sample = HKWorkout(
            activityType: .functionalStrengthTraining,
            start: started,
            end: ended,
            duration: ended.timeIntervalSince(started),
            totalEnergyBurned: energy,
            totalDistance: nil,
            metadata: [HKMetadataKeyExternalUUID: Self.externalID(for: started)]
        )

        lastWriteError = await withCheckedContinuation { continuation in
            store.save(sample) { _, error in continuation.resume(returning: error) }
        }
     }

    /// Replace this workout's sample in Health with an edited one. Writes the
    /// new sample *first*, then deletes the prior one(s) — so a failed write
    /// leaves the original copy untouched rather than a gap. The stale samples
    /// are captured before the write because the new one carries the same
    /// external-UUID stamp; deleting by that stamp afterwards can't tell them
    /// apart.
    func resync(_ workout: Workout, activeEnergyKilocalories: Double) async {
        let stale = await samples(externalID: Self.externalID(for: workout.startedAt))
        await write(workout, activeEnergyKilocalories: activeEnergyKilocalories)
        guard lastWriteError == nil, !stale.isEmpty else { return }
        lastWriteError = await withCheckedContinuation { continuation in
            store.delete(stale) { _, error in continuation.resume(returning: error) }
        }
     }

    /// trackit's stable handle on a workout it wrote to Health: the start
    /// instant at full precision (the sync ledger keys on the same instant, so a
    /// coarser id here could collide for two workouts less than a second apart).
    /// Same `startedAt` ⇒ same id ⇒ an edit replaces rather than duplicates.
    private static func externalID(for startedAt: Date) -> String {
        "trackit-\(startedAt.timeIntervalSinceReferenceDate.bitPattern)"
     }

    /// The workout samples currently in Health under `externalID` (usually one,
    /// none before the first write). An empty result on failure is acceptable —
    /// `resync` then simply skips the delete and leaves the extra copy for the
    /// next edit to clean up.
    private func samples(externalID: String) async -> [HKSample] {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalID]
        )
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
     }
}
