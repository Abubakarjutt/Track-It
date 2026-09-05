// Seam 3 — the workout engine. Owns the workout in progress: applies parser
// results to build the record, and persists every revision synchronously through
// an injected store. Vocabulary follows CONTEXT.md. See specs/v1-voice-logging.md.

import Foundation

/// The record of one training session. See CONTEXT.md ("Workout").
public struct Workout: Equatable, Sendable, Codable {
    /// One slot per exercise, in the order they were first announced.
    public var entries: [Entry]
    /// When `startWorkout()` opened this workout.
    public var startedAt: Date
    /// When `endWorkout()` closed it, or `nil` while it is still active. A `nil`
    /// `endedAt` with an old last set is what stale-workout detection keys on.
    public var endedAt: Date?
    /// A freeform session note the lifter adds after the fact (spec story 48),
    /// or `nil`. Carried only; nothing in the engine reads it.
    public var note: String?

    /// Whether the workout has been closed. Derived from `endedAt` so there is one
    /// source of truth.
    public var isEnded: Bool { endedAt != nil }

    public init(entries: [Entry] = [], startedAt: Date, endedAt: Date? = nil, note: String? = nil) {
        self.entries = entries
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }
}

extension Workout {
    /// When the workout last saw activity: the latest of its start, its most
    /// recent set, and (if closed) its end. A history screen can read this as
    /// "last trained"; stale-workout detection reads it while `endedAt` is nil.
    public var lastActivityAt: Date {
        let lastSet = entries.lazy.flatMap(\.sets).map(\.loggedAt).max()
        return max(startedAt, max(lastSet ?? startedAt, endedAt ?? startedAt))
    }

    /// An open workout idle longer than `threshold` is stale — the lifter almost
    /// certainly forgot to end it, and the app should offer resume-or-close on
    /// launch (spec story 12). An ended workout is never stale.
    public func isStale(now: Date, staleAfter threshold: TimeInterval) -> Bool {
        guard !isEnded else { return false }
        return now.timeIntervalSince(lastActivityAt) > threshold
    }
}

/// One exercise's slot within a workout. See CONTEXT.md ("Entry").
public struct Entry: Equatable, Sendable, Codable {
    public var exercise: Exercise
    /// The sets performed for this exercise, in order.
    public var sets: [LoggedSet]

    public init(exercise: Exercise, sets: [LoggedSet] = []) {
        self.exercise = exercise
        self.sets = sets
    }
}

/// A set as stored in the workout record: the four axes (see ADR-0001) plus
/// canonicalised values. Load is always kilograms (ADR-0002) — the parser's
/// as-spoken `ParsedSet` is converted on the way in. Named `LoggedSet` rather
/// than "Set" (the CONTEXT.md term) to avoid shadowing the standard library.
public struct LoggedSet: Equatable, Sendable, Codable {
    public var loadType: LoadType
    public var effort: EffortMeasure
    public var role: SetRole
    public var grouping: Grouping
    public var loadKilograms: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    /// Which superset run this set belongs to, or `nil` if it is not in one.
    /// Sets sharing an id were logged between the same `superset` / `end superset`
    /// pair; a `.superset` grouping without an id would lose that membership.
    public var supersetRunID: Int?
    /// When the engine received this set. The "last-set timestamp" stale-workout
    /// detection compares against (spec).
    public var loggedAt: Date
    /// A freeform note the lifter attaches to this set after the fact (spec story
    /// 48), or `nil`. Carried only; nothing in the engine reads it.
    public var note: String?

    public init(
        loadType: LoadType,
        effort: EffortMeasure,
        role: SetRole,
        grouping: Grouping,
        loadKilograms: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        supersetRunID: Int? = nil,
        loggedAt: Date,
        note: String? = nil
    ) {
        self.loadType = loadType
        self.effort = effort
        self.role = role
        self.grouping = grouping
        self.loadKilograms = loadKilograms
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.supersetRunID = supersetRunID
        self.loggedAt = loggedAt
        self.note = note
    }
}

/// Persistence boundary. The engine hands the store a full workout revision every
/// time the record changes, so nothing is lost to a crash between "start" and
/// "end". A real implementation is backed by SwiftData; tests use an in-memory fake.
public protocol WorkoutStore: AnyObject {
    func save(_ workout: Workout)
}

/// A working set that set a new best estimated 1RM for its exercise. One is
/// appended to `WorkoutEngine.personalRecords` the instant it happens, for the
/// app's celebratory readback and haptic (spec story 52).
public struct PersonalRecord: Equatable, Sendable, Codable {
    public let exercise: Exercise
    public let estimatedOneRepMaxKilograms: Double

    public init(exercise: Exercise, estimatedOneRepMaxKilograms: Double) {
        self.exercise = exercise
        self.estimatedOneRepMaxKilograms = estimatedOneRepMaxKilograms
    }
}

/// Epley estimated one-rep max (ADR-0003), in the same unit as `load`. A single
/// rep is returned unchanged. Warmup sets are excluded by the caller (spec line
/// 302), not here. Written as `load * (30 + reps) / 30` so round rep counts stay
/// exact.
public func estimatedOneRepMax(loadKilograms load: Double, reps: Int) -> Double {
    reps <= 1 ? load : load * Double(30 + reps) / 30
}

public final class WorkoutEngine {
    /// The rest target used when a template does not set one. Two minutes suits
    /// the compound barbell work this release is built around.
    public static let defaultRestTargetSeconds: TimeInterval = 120

    /// The workout in progress, or `nil` before the first `startWorkout()`.
    public private(set) var workout: Workout?
    /// Personal records set during the workout in progress, in the order they
    /// happened. Reset by `startWorkout()`.
    public private(set) var personalRecords: [PersonalRecord] = []
    /// When the current rest period began — the last set's time, or when
    /// `start rest` was said — or `nil` when no rest is running.
    public private(set) var restStartedAt: Date?

    private let store: WorkoutStore
    private let library: ExerciseLibrary
    /// Best estimated 1RM per exercise (by name) known *before* this workout —
    /// seeded from history. The bar a set must clear to be a personal record.
    private let knownBests: [String: Double]
    /// Running best estimated 1RM per exercise: `knownBests` plus anything beaten
    /// so far this workout.
    private var bestOneRepMax: [String: Double] = [:]
    /// The user's kg/lb preference — the default unit for a set with no spoken unit.
    private var unit: MassUnit
    /// The count-up rest timer's target — the rest period a template does not override.
    private let restTarget: TimeInterval
    /// The engine's clock. Injected so tests can pin timestamps.
    private let now: () -> Date
    /// Index into `workout.entries` that sets and `undo` currently act on. Moves
    /// when an exercise is announced — including *back* to an earlier entry when
    /// an exercise already in the workout is announced again.
    private var activeEntryIndex: Int?
    /// The id of the superset run currently open (between a `superset` marker and
    /// its `end superset`), or `nil` when no run is open. Every set logged while
    /// it is non-nil carries it, so two runs performed back-to-back stay distinct.
    private var currentSupersetRunID: Int?
    /// Count of superset runs opened in this workout — the id source. Reset per
    /// workout, so runs are numbered 1, 2, 3… within each.
    private var supersetRunCount = 0
    /// The last set appended, while it is still the retry target. A re-spoken set
    /// that matches this one overwrites it rather than appending (repeat-to-retry).
    /// Cleared by any announcement, `undo`, or a new workout — the spec's "before
    /// any intervening set" made concrete.
    private var retryTarget: LoggedSet?
    /// Per-exercise (by name) rest targets armed by `startWorkout(from:)`. The
    /// active exercise's entry here overrides `restTarget`. Empty for a workout
    /// not started from a template, or one whose template set no rest targets.
    private var templateRestTargets: [String: TimeInterval] = [:]

    public init(
        store: WorkoutStore,
        library: ExerciseLibrary,
        unit: MassUnit = .kilograms,
        knownBests: [String: Double] = [:],
        restTarget: TimeInterval = WorkoutEngine.defaultRestTargetSeconds,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.library = library
        self.unit = unit
        self.knownBests = knownBests
        self.restTarget = restTarget
        self.now = now
    }

    /// Seconds elapsed in the current rest period, or `nil` if no rest is running.
    public var restElapsedSeconds: TimeInterval? {
        restStartedAt.map { now().timeIntervalSince($0) }
    }

    /// The rest-period target that applies right now: the active exercise's armed
    /// template value if `startWorkout(from:)` set one, otherwise the engine
    /// default. A HUD can show it; `isRestTargetReached` measures against it.
    public var currentRestTargetSeconds: TimeInterval {
        guard let active = activeExerciseName, let armed = templateRestTargets[active]
        else { return restTarget }
        return armed
    }

    /// Whether the current rest has reached its target — the app's cue for the
    /// rest-done haptic and sound (spec story 45). `false` when not resting.
    public var isRestTargetReached: Bool {
        guard let elapsed = restElapsedSeconds else { return false }
        return elapsed >= currentRestTargetSeconds
    }

    /// Opens a fresh workout and persists it. If a workout is still in progress
    /// (the user forgot to say "end workout"), it is closed and persisted first
    /// so it stays a completed workout rather than being silently abandoned.
    public func startWorkout() {
        endWorkout()
        let workout = Workout(startedAt: now())
        self.workout = workout
        activeEntryIndex = nil
        currentSupersetRunID = nil
        supersetRunCount = 0
        retryTarget = nil
        templateRestTargets = [:]
        restStartedAt = nil
        personalRecords = []
        bestOneRepMax = knownBests
        store.save(workout)
    }

    /// Opens a fresh workout with `template`'s per-exercise rest targets armed.
    /// Entries are not pre-created — announcing an exercise is still what adds it.
    public func startWorkout(from template: WorkoutTemplate) {
        startWorkout()
        templateRestTargets = Dictionary(
            template.items.compactMap { item in
                item.restTargetSeconds.map { (item.exercise.name, $0) }
            },
            uniquingKeysWith: { _, last in last }
        )
    }

    /// Adopts an existing, not-yet-ended workout — the launch resume path for a
    /// workout the user forgot to end. Precondition (guarded): `!workout.isEnded`.
    ///
    /// New sets attach to the workout's last entry. The rest timer starts fresh
    /// (a rest period from before the app was killed is meaningless). No
    /// `PersonalRecord` is re-announced for work already in the record — but the
    /// PR bar is seeded from `knownBests` folded with that work, so a set logged
    /// after resuming is a record only if it beats both history and this session.
    ///
    /// Precondition: no workout is already open. The only caller is the launch
    /// composition root, before any `startWorkout`. Unlike `startWorkout()` this
    /// does not close a workout in progress — it overwrites `self.workout`
    /// wholesale — so calling it mid-session would silently drop the open one.
    public func resume(_ workout: Workout) {
        guard !workout.isEnded else { return }

        self.workout = workout
        activeEntryIndex = workout.entries.indices.last
        personalRecords = []
        retryTarget = nil
        currentSupersetRunID = nil
        supersetRunCount = workout.entries
            .flatMap(\.sets)
            .compactMap(\.supersetRunID)
            .max() ?? 0
        templateRestTargets = [:]
        restStartedAt = nil

        var best = knownBests
        for entry in workout.entries {
            for set in entry.sets where set.role == .working {
                guard let load = set.loadKilograms, let reps = set.reps else { continue }
                let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
                best[entry.exercise.name] = max(best[entry.exercise.name] ?? 0, e1rm)
            }
        }
        bestOneRepMax = best

        store.save(workout)
    }

    /// Closes the workout in progress and persists the closed revision.
    public func endWorkout() {
        guard var workout, !workout.isEnded else { return }
        workout.endedAt = now()
        self.workout = workout
        restStartedAt = nil // no rest timer on a closed workout
        store.save(workout)
    }

    /// Corrects the set at `entryIndex` / `setIndex` in the workout in progress —
    /// the mid-workout inline edit path (spec story 38). A no-op when no workout is
    /// open or the index is out of range. Runs the pure `replacingSet` transform,
    /// then re-derives the exercise's running best estimated 1RM (a correction down
    /// must not leave the PR bar too high) and clears the retry target, since a
    /// re-spoken set must never silently overwrite a row the lifter just hand-edited.
    public func editSet(at entryIndex: Int, _ setIndex: Int, with set: LoggedSet) {
        guard let current = openWorkout,
              current.entries.indices.contains(entryIndex),
              current.entries[entryIndex].sets.indices.contains(setIndex)
        else { return }
        let exercise = current.entries[entryIndex].exercise
        mutate { $0 = $0.replacingSet(at: entryIndex, setIndex, with: set) }
        retryTarget = nil
        recomputeBest(for: exercise)
    }

    /// Deletes the set at `entryIndex` / `setIndex` from the workout in progress —
    /// the mid-workout inline delete path (spec story 42). A no-op when no workout
    /// is open or the index is out of range. Runs the pure `removingSet` transform
    /// (which drops the entry if it empties), then re-derives the exercise's best
    /// estimated 1RM, clears the retry target, and re-points `activeEntryIndex` at
    /// the entry that was active before the edit — or at the last entry if that
    /// entry was the one removed, or `nil` if the workout now has no entries. The
    /// rest timer is left running; the lifter may still be resting.
    public func removeSet(at entryIndex: Int, _ setIndex: Int) {
        guard let current = openWorkout,
              current.entries.indices.contains(entryIndex),
              current.entries[entryIndex].sets.indices.contains(setIndex)
        else { return }
        let exercise = current.entries[entryIndex].exercise
        let activeName = activeExerciseName

        mutate { $0 = $0.removingSet(at: entryIndex, setIndex) }

        retryTarget = nil
        recomputeBest(for: exercise)

        if let activeName,
           let restored = workout?.entries.firstIndex(where: { $0.exercise.name == activeName }) {
            activeEntryIndex = restored
        } else {
            activeEntryIndex = workout?.entries.indices.last
        }
    }

    /// Replace the default unit applied to a spoken set that carries no unit
    /// word. Read fresh on each `hear(_:)`, so a change between utterances is
    /// consistent; already-stored sets keep the kilogram value they were
    /// canonicalised to.
    public func updateDefaultUnit(_ unit: MassUnit) {
        self.unit = unit
    }

    /// Interprets one spoken utterance (recogniser n-best in) and applies each
    /// parser result to the workout in progress.
    public func hear(_ hypotheses: [String]) {
        let transcript = postProcess(hypotheses, library: library)
        for result in parse(transcript, context: WorkoutContext(unit: unit), library: library) {
            switch result {
            case .command(.startWorkout):        startWorkout()
            case .command(.endWorkout):          endWorkout()
            case .command(.startSuperset):       beginSupersetRun()
            case .command(.endSuperset):         endSupersetRun()
            case .command(.startRest):           startRest()
            case .command(.skipRest):            skipRest()
            case .announcement(let exercise):    activate(exercise)
            case .set(let parsedSet):            appendSet(grouped(canonicalise(parsedSet, at: now())))
            case .command(.undo):                undoLast()
            case .command, .lowConfidence:       break
            }
        }
    }

    // MARK: - State discipline
    //
    // Every handler below follows the same shape: bail unless `openWorkout` is
    // non-nil, update the engine's session vars (`activeEntryIndex`,
    // `currentSupersetRunID`) directly, and route any change to the persisted
    // record through `mutate`. `mutate` does one thing — transform the `Workout`
    // and save it — and never touches session state.

    /// The workout in progress, but only while it is still open.
    private var openWorkout: Workout? {
        guard let workout, !workout.isEnded else { return nil }
        return workout
    }

    /// The name of the exercise sets currently attach to, or `nil` before the
    /// first announcement (or once the workout is closed). Keyed on for
    /// per-exercise template rest targets.
    private var activeExerciseName: String? {
        guard let index = activeEntryIndex,
              let entries = openWorkout?.entries, entries.indices.contains(index)
        else { return nil }
        return entries[index].exercise.name
    }

    /// Makes `exercise` the active entry: resumes its existing entry if the
    /// workout already has one, otherwise appends a fresh entry for it.
    private func activate(_ exercise: Exercise) {
        guard let current = openWorkout else { return }
        retryTarget = nil // an announcement ends the previous set's retry window
        if let existing = current.entries.firstIndex(where: { $0.exercise == exercise }) {
            activeEntryIndex = existing
        } else {
            mutate { $0.entries.append(Entry(exercise: exercise)) }
            activeEntryIndex = workout?.entries.indices.last
        }
    }

    private func appendSet(_ set: LoggedSet) {
        guard let current = openWorkout, let active = activeEntryIndex,
              current.entries.indices.contains(active) else { return } // no active entry yet
        let exercise = current.entries[active].exercise

        // A re-speak of the last set is a correction, not a new set: overwrite in
        // place, keep the original set's time (the lifter has been resting since
        // then), leave the rest clock alone, and re-derive the PR bar without
        // sounding a fresh celebration.
        if let target = retryTarget, isRetry(of: target, by: set) {
            var corrected = set
            corrected.loggedAt = target.loggedAt
            mutate { workout in
                guard let last = workout.entries[active].sets.indices.last else { return }
                workout.entries[active].sets[last] = corrected
            }
            retryTarget = corrected
            recomputeBest(for: exercise)
            return
        }

        mutate { $0.entries[active].sets.append(set) }
        retryTarget = set
        restStartedAt = set.loggedAt // rest counts up from the set just logged
        recordPersonalBest(set, for: exercise)
    }

    /// Flags a personal record when a working rep set beats the running best
    /// estimated 1RM for its exercise. Warmups and timed / distance efforts are
    /// out (spec line 302). Incremental: the bar only moves up, and every rise is
    /// a new celebratory moment.
    private func recordPersonalBest(_ set: LoggedSet, for exercise: Exercise) {
        guard set.role == .working, let load = set.loadKilograms, let reps = set.reps
        else { return }
        let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
        guard e1rm > (bestOneRepMax[exercise.name] ?? 0) else { return }
        bestOneRepMax[exercise.name] = e1rm
        personalRecords.append(
            PersonalRecord(exercise: exercise, estimatedOneRepMaxKilograms: e1rm)
        )
    }

    /// Re-derives the running best estimated 1RM for `exercise` from the
    /// pre-workout seed plus every working rep set now in the record. Used after a
    /// correction, where `recordPersonalBest` — which only ever raises the bar —
    /// would leave it stale: too high after a correction down, double-counted
    /// after a correction up. Never appends a `PersonalRecord`; a fix is not a
    /// new moment.
    private func recomputeBest(for exercise: Exercise) {
        let sets = (workout?.entries ?? []).lazy
            .filter { $0.exercise == exercise }
            .flatMap(\.sets)
        bestOneRepMax[exercise.name] = sets.reduce(knownBests[exercise.name] ?? 0) { best, set in
            guard set.role == .working, let load = set.loadKilograms, let reps = set.reps
            else { return best }
            return max(best, estimatedOneRepMax(loadKilograms: load, reps: reps))
        }
    }

    /// Removes the last thing appended to the active entry: its last set, or the
    /// entry itself if it was only just announced.
    private func undoLast() {
        guard let current = openWorkout, let active = activeEntryIndex,
              current.entries.indices.contains(active) else { return }
        retryTarget = nil
        if current.entries[active].sets.isEmpty {
            mutate { $0.entries.remove(at: active) }
            activeEntryIndex = workout?.entries.indices.last
        } else {
            mutate { $0.entries[active].sets.removeLast() }
        }
    }

    /// Repeat-to-retry: `candidate` is a re-speak of `existing` when everything
    /// matches except the timestamp and, for rep sets, a rep count within
    /// `retryRepTolerance` — the recogniser mishearing "five" as "eight". A larger
    /// gap is a real back-off set, so it appends. (Conservative until the audio
    /// corpus can tune it; load, duration and distance must still match exactly.)
    private func isRetry(of existing: LoggedSet, by candidate: LoggedSet) -> Bool {
        // Compare every field except reps and timestamp: copy the target's values
        // into those two slots so `==` decides the rest, then check reps on their
        // own against the tolerance below.
        var normalised = candidate
        normalised.loggedAt = existing.loggedAt
        normalised.reps = existing.reps
        guard normalised == existing else { return false }

        switch (candidate.reps, existing.reps) {
        case let (new?, old?): return abs(new - old) <= retryRepTolerance
        case (nil, nil):       return true // a timed / distance set, matched exactly above
        default:               return false
        }
    }

    /// Starts the rest timer from now. Ignored when no workout is open.
    private func startRest() {
        guard openWorkout != nil else { return }
        restStartedAt = now()
    }

    /// Stops the rest timer. Idempotent — like `endSupersetRun()`, clearing to
    /// `nil` cannot corrupt state, so it needs no guard.
    private func skipRest() {
        restStartedAt = nil
    }

    /// Opens a new superset run: sets logged until `endSupersetRun()` share its id.
    private func beginSupersetRun() {
        guard openWorkout != nil else { return }
        supersetRunCount += 1
        currentSupersetRunID = supersetRunCount
    }

    /// Closes the open superset run. Idempotent — clearing to `nil` cannot corrupt
    /// state, so it needs no `openWorkout` guard.
    private func endSupersetRun() {
        currentSupersetRunID = nil
    }

    /// Stamps `.superset` grouping and the current run id while a run is open,
    /// leaving the parser's grouping (e.g. `.dropset`) untouched otherwise.
    private func grouped(_ set: LoggedSet) -> LoggedSet {
        guard let runID = currentSupersetRunID else { return set }
        var set = set
        set.grouping = .superset
        set.supersetRunID = runID
        return set
    }

    private func mutate(_ change: (inout Workout) -> Void) {
        guard var workout, !workout.isEnded else { return }
        change(&workout)
        self.workout = workout
        store.save(workout)
    }
}

private let poundsToKilograms = 0.45359237

/// How far a re-spoken set's rep count may differ from the last set's and still
/// count as a correction rather than a new set. See `isRetry`.
private let retryRepTolerance = 3

/// Converts the parser's as-spoken `ParsedSet` into the stored form, with the
/// load in kilograms (ADR-0002) and the receipt time stamped on.
private func canonicalise(_ set: ParsedSet, at time: Date) -> LoggedSet {
    LoggedSet(
        loadType: set.loadType,
        effort: set.effort,
        role: set.role,
        grouping: set.grouping,
        loadKilograms: kilograms(set.load, in: set.loadUnit),
        reps: set.reps,
        durationSeconds: set.durationSeconds,
        distanceMeters: set.distanceMeters,
        loggedAt: time
    )
}

private func kilograms(_ load: Double?, in unit: MassUnit?) -> Double? {
    guard let load else { return nil }
    switch unit {
    case .pounds:            return load * poundsToKilograms
    case .kilograms, .none:  return load
    }
}
