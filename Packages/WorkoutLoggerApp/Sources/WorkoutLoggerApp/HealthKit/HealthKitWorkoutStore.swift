import Foundation
import WorkoutLoggerCore

/// The flattened HealthKit authorization state the Settings UI distinguishes.
/// `unavailable` means the device has no HealthKit (e.g. a Mac or a restricted
/// device) — there is no toggle to offer, and no "Open iOS Settings" link to
/// take back.
public enum HealthKitSyncStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

/// The slice of HealthKit a completed workout needs: its current
/// authorization state, a way to request that authorization, and a non-throwing
/// write of one strength-training workout with a rough active-energy figure.
/// The real implementation wraps `HKHealthStore` (in `App/`, files-only); a
/// fake that records what it was written drives the model tests.
@MainActor
public protocol HealthKitWorkoutStore: AnyObject {
    var status: HealthKitSyncStatus { get }
    var lastWriteError: Error? { get }
    func request() async
    func write(_ workout: Workout, activeEnergyKilocalories: Double)
}
