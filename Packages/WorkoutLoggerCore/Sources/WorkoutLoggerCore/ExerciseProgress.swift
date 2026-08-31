// Per-exercise progress — folds a list of stored workouts into a per-session
// summary the progress screen draws. Pure: no engine, no store. Operates on
// stored kilogram sets (ADR-0002) and reuses `estimatedOneRepMax` (ADR-0003).
// See specs/v1-voice-logging.md (stories 49–50).

import Foundation

/// One exercise's history, oldest session first.
public struct ExerciseProgress: Equatable, Sendable {
    /// One entry per workout in `history` that included the exercise, in the
    /// order the workouts were given.
    public var sessions: [ExerciseSession]

    /// The highest per-session estimated 1RM across all of `sessions`, or `nil`
    /// if the exercise was never trained for reps. This is the exercise's
    /// personal record (CONTEXT.md — "one value per exercise") and the value to
    /// seed `WorkoutEngine`'s `knownBests` with from history.
    public var bestEstimatedOneRepMaxKilograms: Double? {
        sessions.compactMap(\.bestEstimatedOneRepMaxKilograms).max()
    }

    public init(sessions: [ExerciseSession]) {
        self.sessions = sessions
    }
}

/// What one workout did for one exercise.
public struct ExerciseSession: Equatable, Sendable {
    /// The workout's start time — the x-axis point for this session.
    public var date: Date
    /// Total tonnage for the exercise this session: Σ (load × reps) across its
    /// working sets (CONTEXT.md "Volume"). Warmups do not count.
    public var volumeKilograms: Double
    /// Σ reps across the session's working sets, load or no load. The progression
    /// signal for bodyweight work (story 25), where `volumeKilograms` is zero.
    /// Warmups and timed / distance sets do not count.
    public var workingReps: Int
    /// The heaviest working set's load this session, or `nil` when no working set
    /// carried a stored load (a pure bodyweight session). Warmups do not count.
    public var topSetLoadKilograms: Double?
    /// The highest Epley estimate (ADR-0003) across the session's working *rep*
    /// sets, or `nil` when none had both a load and a rep count. The per-session
    /// point of the estimated-1RM trend (story 50).
    public var bestEstimatedOneRepMaxKilograms: Double?

    public init(
        date: Date,
        volumeKilograms: Double,
        workingReps: Int,
        topSetLoadKilograms: Double?,
        bestEstimatedOneRepMaxKilograms: Double?
    ) {
        self.date = date
        self.volumeKilograms = volumeKilograms
        self.workingReps = workingReps
        self.topSetLoadKilograms = topSetLoadKilograms
        self.bestEstimatedOneRepMaxKilograms = bestEstimatedOneRepMaxKilograms
    }
}

/// Folds every workout in `history` that used `exercise` into an `ExerciseSession`.
public func exerciseProgress(for exercise: Exercise, across history: [Workout]) -> ExerciseProgress {
    let sessions = history.compactMap { workout -> ExerciseSession? in
        let sets = workout.entries
            .filter { $0.exercise == exercise }
            .flatMap(\.sets)
        guard !sets.isEmpty else { return nil }

        let working = sets.filter { $0.role == .working }
        let volume = working.reduce(0.0) { running, set in running + volumeContribution(of: set) }
        let reps = working.reduce(0) { running, set in running + (set.reps ?? 0) }
        let topSet = working.compactMap(\.loadKilograms).max()
        let bestEstimate = working.compactMap(estimatedOneRepMax(of:)).max()

        return ExerciseSession(
            date: workout.startedAt,
            volumeKilograms: volume,
            workingReps: reps,
            topSetLoadKilograms: topSet,
            bestEstimatedOneRepMaxKilograms: bestEstimate
        )
    }
    return ExerciseProgress(sessions: sessions)
}

/// How much one working set adds to Volume: `load × reps`. A set with no stored
/// load (pure bodyweight work) or no reps (a timed / distance effort) contributes
/// nothing — this pure function has no access to the lifter's bodyweight, so it
/// cannot turn bodyweight reps into real tonnage. Revisit when the bodyweight
/// progress slice lands.
private func volumeContribution(of set: LoggedSet) -> Double {
    guard let load = set.loadKilograms, let reps = set.reps else { return 0 }
    return load * Double(reps)
}

/// The Epley estimate for one set, or `nil` when it lacks a load or a rep count
/// (bodyweight or timed work) — those sets do not contribute to the trend.
private func estimatedOneRepMax(of set: LoggedSet) -> Double? {
    guard let load = set.loadKilograms, let reps = set.reps else { return nil }
    return estimatedOneRepMax(loadKilograms: load, reps: reps)
}
