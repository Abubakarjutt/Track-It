// Personal-record detection and the running estimated-1RM bar, split out of
// WorkoutEngine (1e). A value type the engine owns one of; the logic here moved
// from the engine with mechanical changes only — `recompute` now takes its set
// list as a parameter, and `foldIn` is a new name for the loop that lived inline
// in `resume` — and is behaviour-preserving.

import Foundation

/// Tracks the running best estimated 1RM per exercise for the workout in
/// progress and flags each working set that raises it.
///
/// Three layers of "best":
/// - `seed` — the launch-time fallback, immutable for the tracker's life.
/// - `workoutSeed` — the pre-workout floor snapshotted by `reseed()`: the live
///   provider's view of history when one is injected (1a), else `seed`. A
///   correction folds this workout's sets back over *this*, never over `running`.
/// - `running` — `workoutSeed` plus everything beaten so far this workout.
///
/// Keyed on the whole `Exercise` value (1d).
struct PRTracker {
    private let seed: [Exercise: Double]
    /// A live source of pre-workout bests, or `nil` to keep `seed`. Not
    /// `@Sendable` — like the engine's clock it is read only on the owning actor.
    private let provider: (() -> [Exercise: Double])?
    private var workoutSeed: [Exercise: Double] = [:]
    private var running: [Exercise: Double] = [:]
    /// Records set during the workout in progress, in the order they happened.
    private(set) var personalRecords: [PersonalRecord] = []

    init(seed: [Exercise: Double], provider: (() -> [Exercise: Double])?) {
        self.seed = seed
        self.provider = provider
    }

    /// Reloads the pre-workout floor from the provider (or `seed`), resets the
    /// running bar to it, and clears this workout's records. Called when a fresh
    /// workout opens or a stale one is resumed.
    mutating func reseed() {
        workoutSeed = provider?() ?? seed
        running = workoutSeed
        personalRecords = []
    }

    /// Folds `set` into the running bar. When a working rep set beats the bar,
    /// raises it, appends a `PersonalRecord`, and returns it; otherwise returns
    /// `nil`. Warmups and timed / distance efforts never count (spec line 302).
    @discardableResult
    mutating func record(_ set: LoggedSet, for exercise: Exercise) -> PersonalRecord? {
        guard set.role == .working, let load = set.loadKilograms, let reps = set.reps
        else { return nil }
        let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
        guard e1rm > (running[exercise] ?? 0) else { return nil }
        running[exercise] = e1rm
        let record = PersonalRecord(exercise: exercise, estimatedOneRepMaxKilograms: e1rm)
        personalRecords.append(record)
        return record
    }

    /// Re-derives the running bar for `exercise` from the pre-workout floor plus
    /// `sets` (every set logged for it so far). Used after a correction, which
    /// `record` — only ever raising the bar — would leave stale. Never appends a
    /// `PersonalRecord`; a fix is not a new moment.
    mutating func recompute(for exercise: Exercise, from sets: [LoggedSet]) {
        running[exercise] = sets.reduce(workoutSeed[exercise] ?? 0) { best, set in
            guard set.role == .working, let load = set.loadKilograms, let reps = set.reps
            else { return best }
            return max(best, estimatedOneRepMax(loadKilograms: load, reps: reps))
        }
    }

    /// Folds a resumed workout's existing work into the running bar so a set
    /// logged after resuming is a record only if it beats both history and the
    /// sets already here. Leaves `workoutSeed` — the pure pre-workout floor —
    /// untouched. No `PersonalRecord` is appended for work already in the record.
    mutating func foldIn(_ workout: Workout) {
        for entry in workout.entries {
            for set in entry.sets where set.role == .working {
                guard let load = set.loadKilograms, let reps = set.reps else { continue }
                let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
                running[entry.exercise] = max(running[entry.exercise] ?? 0, e1rm)
            }
        }
    }
}
