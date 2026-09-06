import Foundation
import WorkoutLoggerCore

/// A deliberately rough active-energy figure for a completed workout, in
/// kilocalories. Duration only — trackit never reads HealthKit (sync is
/// one-way, spec F2), so there is no body mass to work from. `6.0` kcal/min is
/// ≈ MET 5 at a 72 kg reference body mass; a workout still in progress
/// (`endedAt == nil`) estimates zero.
public func estimatedActiveEnergyKilocalories(for workout: Workout) -> Double {
    guard let endedAt = workout.endedAt else { return 0 }
    let minutes = max(0, endedAt.timeIntervalSince(workout.startedAt) / 60)
    return minutes * 6.0
}
