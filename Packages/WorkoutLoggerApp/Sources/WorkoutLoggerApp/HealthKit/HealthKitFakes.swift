import Foundation
import WorkoutLoggerCore

/// A `HealthKitWorkoutStore` for tests: starts at `status`, and `request()`
/// moves it to `statusAfterRequest` and bumps `authorizationRequests`. Every
/// `write` is recorded on `saved` so a test can assert one workout, its
/// timing, and its rough energy. HealthKit-free — the model seam is what the
/// tests cover, not the system store.
@MainActor
public final class FakeHealthKitWorkoutStore: HealthKitWorkoutStore {
    public private(set) var status: HealthKitSyncStatus
    public private(set) var lastWriteError: Error?
    public private(set) var authorizationRequests = 0

    /// Each written workout with its rough active-energy figure, in write order.
    public struct SavedWorkout {
        public let workout: Workout
        public let activeEnergyKilocalories: Double
    }
    public private(set) var saved: [SavedWorkout] = []

    private let statusAfterRequest: HealthKitSyncStatus

    public init(
        status: HealthKitSyncStatus = .notDetermined,
        statusAfterRequest: HealthKitSyncStatus = .authorized
      ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
      }

    public func request() async {
        authorizationRequests += 1
        status = statusAfterRequest
      }

    public func write(_ workout: Workout, activeEnergyKilocalories: Double) {
        saved.append(SavedWorkout(workout: workout, activeEnergyKilocalories: activeEnergyKilocalories))
      }

    /// Test hook: simulate a permission change the user makes elsewhere
    /// (the Health app, or iOS Settings) that the model re-reads.
    public func set(_ status: HealthKitSyncStatus) {
        self.status = status
    }
}
