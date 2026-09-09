// The count-up rest clock, split out of WorkoutEngine (1e). A small value type:
// the engine owns one instance and forwards its public rest accessors here,
// holding no rest state of its own. Behaviour-preserving — see WorkoutEngine.

import Foundation

/// The rest period between sets, measured up from when it began. A logged set or
/// a `start rest` command opens a period; `skip()` / `reset()` close it. A
/// template can arm per-exercise targets that override `defaultTarget` for the
/// exercise they name.
struct RestTimer {
    /// The target used when no armed template target covers the active exercise.
    let defaultTarget: TimeInterval
    /// When the current rest period began, or `nil` when none is running.
    private(set) var startedAt: Date?
    /// Per-exercise targets armed by `startWorkout(from:)`, keyed on the whole
    /// `Exercise` value (1d). Empty for a workout not started from a template.
    private var armed: [Exercise: TimeInterval] = [:]

    init(defaultTarget: TimeInterval) {
        self.defaultTarget = defaultTarget
    }

    /// Begins a rest period at `date` — a `start rest` command (`now`) or the
    /// timestamp of the set just logged.
    mutating func start(at date: Date) {
        startedAt = date
    }

    /// Stops the timer. Idempotent — clearing to `nil` cannot corrupt state.
    mutating func skip() {
        startedAt = nil
    }

    /// Arms per-exercise targets from a template, replacing any previous set.
    mutating func arm(_ targets: [Exercise: TimeInterval]) {
        armed = targets
    }

    /// Clears both the running period and any armed targets — a fresh workout.
    mutating func reset() {
        startedAt = nil
        armed = [:]
    }

    /// Seconds elapsed in the current rest period, or `nil` if none is running.
    func elapsed(now: Date) -> TimeInterval? {
        startedAt.map { now.timeIntervalSince($0) }
    }

    /// The target that applies right now: the active exercise's armed value if
    /// one was set, otherwise `defaultTarget`.
    func currentTarget(activeExercise: Exercise?) -> TimeInterval {
        activeExercise.flatMap { armed[$0] } ?? defaultTarget
    }

    /// Whether the current rest has reached its target. `false` when not resting.
    func targetReached(now: Date, activeExercise: Exercise?) -> Bool {
        elapsed(now: now).map { $0 >= currentTarget(activeExercise: activeExercise) } ?? false
    }
}
