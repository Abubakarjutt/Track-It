import Foundation
import WorkoutLoggerCore

/// The slice of persistence the history and progress models need: read all
/// stored workouts, write one back, and see whether the last write failed.
/// `SwiftDataWorkoutStore` already has every member.
public protocol WorkoutHistoryStore: AnyObject {
    func history() -> [Workout]
    func save(_ workout: Workout)
    var lastSaveError: Error? { get }
}

extension SwiftDataWorkoutStore: WorkoutHistoryStore {}
