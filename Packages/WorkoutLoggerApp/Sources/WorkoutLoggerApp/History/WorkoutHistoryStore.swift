import Foundation
import WorkoutLoggerCore

/// The slice of persistence the history and progress models need: read all
/// stored workouts, write one back, and see whether the last write failed.
/// `SwiftDataWorkoutStore` already has every member.
public protocol WorkoutHistoryStore: AnyObject {
    func history() -> [Workout]
    func save(_ workout: Workout)
    /// Remove every stored workout. Anything else in the same container
    /// (the exercise library) is left untouched.
    func deleteAllWorkouts()
    /// Remove the one stored workout keyed on `startedAt`. A `startedAt` that
    /// matches nothing is a no-op. A failure is surfaced through `lastSaveError`.
    func deleteWorkout(startedAt: Date)
    var lastSaveError: Error? { get }
}

extension SwiftDataWorkoutStore: WorkoutHistoryStore {}
