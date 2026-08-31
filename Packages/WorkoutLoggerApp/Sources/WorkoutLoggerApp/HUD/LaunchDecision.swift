import Foundation
import WorkoutLoggerCore

/// What to do with persistence state at launch.
public enum LaunchDecision: Equatable, Sendable {
    /// No open workout — start clean.
    case fresh
    /// An open workout touched recently enough to reopen without asking.
    case resume(Workout)
    /// An open workout stale enough that the user should choose resume-or-discard.
    case promptStale(Workout)
}

/// Classifies the workout (if any) returned by `SwiftDataWorkoutStore.openWorkout()`.
/// `staleAfter` is the idle span past which an open workout is treated as
/// forgotten rather than in-progress.
public func launchDecision(
    openWorkout: Workout?,
    now: Date,
    staleAfter: TimeInterval = 6 * 60 * 60
) -> LaunchDecision {
    guard let workout = openWorkout, !workout.isEnded else { return .fresh }
    return workout.isStale(now: now, staleAfter: staleAfter)
        ? .promptStale(workout)
        : .resume(workout)
}

/// The discard branch of `.promptStale`: close the workout at the moment it was
/// last touched (not `now` — it ended whenever the user stopped logging) and
/// persist it. Nothing is deleted; the app then proceeds as `.fresh`.
public func closeAbandonedWorkout(_ workout: Workout, in store: SwiftDataWorkoutStore) {
    var closed = workout
    closed.endedAt = workout.lastActivityAt
    store.save(closed)
}
