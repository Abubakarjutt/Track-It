// Per-exercise progress — folds a list of stored workouts into a per-session
// summary the progress screen draws. Pure: no engine, no store. Operates on
// stored kilogram sets (ADR-0002); `epleyEstimate(of:)` wraps the engine's
// `estimatedOneRepMax(loadKilograms:reps:)` (ADR-0003).
// See specs/v1-voice-logging.md (stories 49–50).

import Foundation

/// One exercise's history, oldest session first.
public struct ExerciseProgress: Equatable, Sendable {
    /// One entry per workout in `history` that included the exercise, in the
    /// order the workouts were given.
    public let sessions: [ExerciseSession]

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
    public let date: Date
    /// Total tonnage for the exercise this session: Σ (load × reps) across its
    /// working sets (CONTEXT.md "Volume"). Warmups do not count.
    public let volumeKilograms: Double
    /// Σ reps across the session's working sets, load or no load. The progression
    /// signal for bodyweight work (story 25), where `volumeKilograms` is zero.
    /// Warmups and timed / distance sets do not count.
    public let workingReps: Int

     /// The session's set volume — the count of its working sets (CONTEXT.md
     /// "Set volume"), the per-session training-stimulus gauge, distinct from
     /// `volumeKilograms` (tonnage). Warmups do not count.
    public let workingSetCount: Int
    /// The heaviest working set's load this session, or `nil` when no working set
    /// carried a stored load (a pure bodyweight session). Warmups do not count.
    public let topSetLoadKilograms: Double?
    /// The highest Epley estimate (ADR-0003) across the session's working *rep*
    /// sets, or `nil` when none had both a load and a rep count. The per-session
    /// point of the estimated-1RM trend (story 50).
    public let bestEstimatedOneRepMaxKilograms: Double?

    public init(
        date: Date,
        volumeKilograms: Double,
        workingReps: Int,
        workingSetCount: Int,
        topSetLoadKilograms: Double?,
        bestEstimatedOneRepMaxKilograms: Double?
    ) {
        self.date = date
        self.volumeKilograms = volumeKilograms
        self.workingReps = workingReps
        self.workingSetCount = workingSetCount
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
        let workingSetCount = working.count
        let topSet = working.compactMap(\.loadKilograms).max()
        let bestEstimate = working.compactMap(epleyEstimate(of:)).max()

        return ExerciseSession(
            date: workout.startedAt,
            volumeKilograms: volume,
            workingReps: reps,
            workingSetCount: workingSetCount,
            topSetLoadKilograms: topSet,
            bestEstimatedOneRepMaxKilograms: bestEstimate
        )
    }
    return ExerciseProgress(sessions: sessions)
}

/// The count of a workout's working sets — its total **set volume** (CONTEXT.md
/// "Set volume"), the per-workout training-stimulus gauge, distinct from Volume
/// (Σ load × reps). Warmups never count; a superset / dropset contributes one
/// per working set entry it holds, so a two-exercise superset round is two sets.
public func workoutSetVolume(_ workout: Workout) -> Int {
    workout.entries.reduce(0) { running, entry in
        running + workingSets(of: entry).count
     }
}

/// Each exercise's working-set count across one workout, keyed by the whole
/// `Exercise` value (it is `Hashable`). A second entry for the same exercise
/// merges into one count; an exercise with no working set is absent from the
/// result. Warmups never count. Reconciles with `workoutSetVolume(_:)` — the
/// latter is the sum of this function's values.
public func workoutSetVolumeByExercise(_ workout: Workout) -> [Exercise: Int] {
    var counts: [Exercise: Int] = [:]
    for entry in workout.entries {
        let working = workingSets(of: entry).count
        if working > 0 {
            counts[entry.exercise, default: 0] += working
         }
     }
    return counts
}

/// The working sets of one entry — the sets that count toward volume and set
/// volume. Warmups are excluded everywhere (CONTEXT.md "Set volume"); a set with
/// no reps (timed / distance) or no load (bodyweight) is still a working set and
/// still counts toward set volume.
private func workingSets(of entry: Entry) -> [LoggedSet] {
    entry.sets.filter { $0.role == .working }
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
/// (bodyweight or timed work) — those sets do not contribute to the trend. Named
/// so it reads clearly next to the public `estimatedOneRepMax(loadKilograms:reps:)`
/// it wraps, rather than shadowing that name with a second overload.
private func epleyEstimate(of set: LoggedSet) -> Double? {
    guard let load = set.loadKilograms, let reps = set.reps else { return nil }
    return estimatedOneRepMax(loadKilograms: load, reps: reps)
}
