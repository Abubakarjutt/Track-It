import Foundation
import Observation
import WorkoutLoggerCore

/// A stale open workout found at launch, plus the two ways to resolve it. The
/// composition root supplies the closures (`engine.resume` / `closeAbandonedWorkout`);
/// the model just exposes the pending workout and calls one closure when the
/// user picks.
public struct StaleWorkoutRecovery {
    public let workout: Workout
    public let onResume: () -> Void
    public let onDiscard: () -> Void

    public init(workout: Workout, onResume: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        self.workout = workout
        self.onResume = onResume
        self.onDiscard = onDiscard
    }
}

/// The single object the view layer binds to. Owns a `WorkoutEngine`, forwards
/// spoken utterances into it, copies its state out into observed properties, and
/// drives readback + haptics from what the parser produced.
@MainActor
@Observable
public final class WorkoutSessionModel {
    public private(set) var workout: Workout?
    public private(set) var personalRecords: [PersonalRecord] = []
    public private(set) var restStartedAt: Date?
    public private(set) var restElapsed: TimeInterval = 0
    public private(set) var isListening = false
    public private(set) var tapSelectCandidates: [Exercise]?
    public private(set) var lastReadback: ReadbackPlan?
    /// The rest target the timer counts toward right now — the active exercise's
    /// template value if one is armed, else the engine default. For a "1:23 / 2:00"
    /// style display.
    public private(set) var restTargetSeconds: TimeInterval = WorkoutEngine.defaultRestTargetSeconds
    /// Whether the current rest has reached its target. Snapshot of the engine,
    /// refreshed on every `tick()` because it moves with the clock.
    public private(set) var isRestTargetReached = false
    /// A stale open workout awaiting the user's resume-or-discard choice, or nil.
    public private(set) var staleRecovery: StaleWorkoutRecovery?
    /// The exercise the next set will be logged against. Tracks the engine's
    /// active entry, which moves *back* to an earlier exercise when the lifter
    /// re-announces it — so this is not always `workout.entries.last`. Mirrored
    /// here because the engine keeps its active index private and the core is
    /// frozen. `nil` when no workout is open.
    public private(set) var activeExerciseName: String?
    /// A one-line summary of the last completed workout for the active exercise —
    /// its heaviest working-set load and best estimated 1RM — or `nil` when the
    /// exercise has no prior history. Feeds the HUD "vs last time" row. Load and
    /// estimate only: `ExerciseSession` carries no rep count.
    public private(set) var previousWorkoutLine: String?
    /// True right after a tap-select shortlist was dismissed without a pick —
    /// the spoken set was real but is now gone, and on an eyes-free app a
    /// silent drop is indistinguishable from a successful log. Cleared by the
    /// next `pressed()`, so it only lives until the user acts again.
    public private(set) var notLoggedNotice = false
    /// True across the async gap between releasing the talk button and the
    /// transcript resolving — recognition finalizing, parse running, engine
    /// applying. The lifter's finger is already off the button here, so
    /// without this the HUD would silently sit idle mid-work.
    public private(set) var isProcessing = false

    @ObservationIgnored private let engine: WorkoutEngine
    @ObservationIgnored private let transcriptSource: TranscriptSource
    @ObservationIgnored private let readbackVoice: ReadbackVoice
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private var library: ExerciseLibrary
    @ObservationIgnored private var unit: MassUnit
    @ObservationIgnored private let capReadbackAtEarcon: Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var knownBestExercises: Set<String>
    @ObservationIgnored private let history: () -> [Workout]

    @ObservationIgnored private var announcedThisWorkout: Set<String> = []
    @ObservationIgnored private var lastTranscript = ""
    @ObservationIgnored private var restReachedFired = false
    @ObservationIgnored private var inFlightReleases = 0

    public init(
        engine: WorkoutEngine,
        transcriptSource: TranscriptSource,
        readbackVoice: ReadbackVoice,
        haptics: Haptics,
        library: ExerciseLibrary,
        unit: MassUnit = .kilograms,
        capReadbackAtEarcon: Bool = false,
        now: @escaping () -> Date = Date.init,
        knownBestExercises: Set<String> = [],
        staleRecovery: StaleWorkoutRecovery? = nil,
        history: @escaping () -> [Workout] = { [] }
    ) {
        self.engine = engine
        self.transcriptSource = transcriptSource
        self.readbackVoice = readbackVoice
        self.haptics = haptics
        self.library = library
        self.unit = unit
        self.capReadbackAtEarcon = capReadbackAtEarcon
        self.now = now
        self.knownBestExercises = knownBestExercises
        self.staleRecovery = staleRecovery
        self.history = history
        syncFromEngine()
        seedAnnouncedFromCurrentWorkout()
    }

    /// When constructed over a workout already in progress (the resume path),
    /// treat its exercises as already announced this workout so the next readback
    /// for one is terse.
    private func seedAnnouncedFromCurrentWorkout() {
        defer { refreshPreviousWorkoutLine() }
        guard let workout, !workout.isEnded else {
            activeExerciseName = nil
            return
        }
        announcedThisWorkout = Set(workout.entries.map(\.exercise.name))
        // `WorkoutEngine.resume` points its active entry at the last one.
        activeExerciseName = workout.entries.last?.exercise.name
    }

    /// The workout the launch prompt is asking about, if any.
    public var pendingStaleWorkout: Workout? { staleRecovery?.workout }

    /// The user chose to resume the stale workout.
    public func resumePendingStaleWorkout() {
        staleRecovery?.onResume()
        staleRecovery = nil
        syncFromEngine()
        seedAnnouncedFromCurrentWorkout()
    }

    /// The user chose to discard the stale workout. The engine never adopts it;
    /// the closure closes it in storage at its last-activity time.
    public func discardPendingStaleWorkout() {
        staleRecovery?.onDiscard()
        staleRecovery = nil
        syncFromEngine()
    }

    /// The unit the HUD formats loads in — the injected preference.
    public var displayUnit: MassUnit { unit }

    /// Replace the default kg/lb unit live. Updates the copy this model uses
    /// for its own inspection parse and forwards to the engine, which owns
    /// the authoritative apply. Display-only for already-logged sets.
    public func updateDefaultUnit(_ unit: MassUnit) {
        self.unit = unit
        engine.updateDefaultUnit(unit)
    }

    /// Replace the exercise library live, on both this model's inspection
    /// parse and the engine's authoritative one.
    public func updateLibrary(_ library: ExerciseLibrary) {
        self.library = library
        engine.updateLibrary(library)
    }

    /// True while a workout is open; the view maps it to `isIdleTimerDisabled`.
    public var keepScreenAwake: Bool {
        guard let workout else { return false }
        return !workout.isEnded
    }

    public func pressed() {
        transcriptSource.beginUtterance()
        isListening = true
        notLoggedNotice = false
    }

    public func released() async {
        isListening = false
        // A depth counter, not a flag: a quick press-release-press-release
        // (plausible when a lifter thinks the first one didn't take) starts
        // a second released() while the first is still awaiting its
        // transcript. A plain Bool would let the first call's `defer` clear
        // isProcessing out from under the second, showing "Hold to talk"
        // while a transcript is still being resolved.
        inFlightReleases += 1
        isProcessing = true
        defer {
            inFlightReleases -= 1
            isProcessing = inFlightReleases > 0
        }
        let hypotheses: [String]
        do {
            hypotheses = try await transcriptSource.endUtterance()
        } catch {
            // No transcript means no parse and no engine call — but on an
            // eyes-free app a silent return is indistinguishable from a freeze,
            // so the failure still gets a haptic and an earcon.
            haptics.play(.notCaught)
            readbackVoice.perform(.earcon)
            return
        }
        apply(hypotheses)
    }

    public func resolveTapSelect(_ exercise: Exercise) {
        guard tapSelectCandidates != nil else { return }
        tapSelectCandidates = nil
        apply([rewrite(lastTranscript, toName: exercise.name)])
    }

    /// Dismiss the tap-select shortlist without picking anything. The pending
    /// utterance is dropped and the workout is left exactly as it was.
    ///
    /// A no-op when there's no shortlist up — the HUD's shared sheet binding
    /// calls this on every dismissal, including closing the unrelated set
    /// list, so without this guard closing that sheet would falsely raise
    /// "Not logged" over a set that was never spoken.
    public func dismissTapSelect() {
        guard tapSelectCandidates != nil else { return }
        tapSelectCandidates = nil
        notLoggedNotice = true
        // Same eyes-free rule as the endUtterance failure path in released():
        // a dropped set gets a haptic and an earcon, not just a footnote the
        // lifter isn't looking at.
        haptics.play(.notCaught)
        readbackVoice.perform(.earcon)
    }

    public func tick() {
        guard let startedAt = restStartedAt else {
            restElapsed = 0
            isRestTargetReached = false
            return
        }
        restElapsed = now().timeIntervalSince(startedAt)
        isRestTargetReached = engine.isRestTargetReached
        if engine.isRestTargetReached, !restReachedFired {
            restReachedFired = true
            haptics.play(.restReached)
        }
    }

    // MARK: - Applying an utterance

    private func apply(_ hypotheses: [String]) {
        let transcript = postProcess(hypotheses, library: library)
        lastTranscript = transcript
        let results = parse(transcript, context: WorkoutContext(unit: unit), library: library)

        if results.contains(where: { isStartWorkout($0) }) {
            announcedThisWorkout = []
        }

        let setsBefore = totalSetCount(workout)
        let prBefore = engine.personalRecords.count
        let workoutBefore = workout

        engine.hear(hypotheses)
        syncFromEngine()
        updateActiveExercise(from: results)

        if workoutBefore?.isEnded == false, workout?.isEnded == true {
            knownBestExercises = Self.exercisesWithLoadedWorkingSet(in: history())
        }

        let setsAfter = totalSetCount(workout)
        let loggedASet = setsAfter > setsBefore

        let genuinePR = engine.personalRecords
            .dropFirst(prBefore)
            .contains { isGenuinePersonalRecord($0.exercise.name, before: workoutBefore) }

        fireHaptic(results: results, loggedASet: loggedASet, firePersonalRecord: genuinePR)
        speakReadback(results: results)
        captureTapSelect(results: results)

        if loggedASet {
            restReachedFired = false
            // A new set restarts rest; `restStartedAt` re-syncs from the engine
            // but `restElapsed` is only recomputed in `tick()`, so zero it now
            // rather than show the previous period's value for up to a second.
            restElapsed = 0
        }
    }

    private func fireHaptic(results: [ParseResult], loggedASet: Bool, firePersonalRecord: Bool) {
        if loggedASet {
            haptics.play(.logged)
            if firePersonalRecord { haptics.play(.personalRecord) }
            return
        }
        if results.contains(where: { isLowConfidence($0) }) {
            haptics.play(.notCaught)
        }
    }

    /// A new best is genuine — worth the celebration haptic — when the exercise
    /// had a seeded historical best, or already had a working set this workout
    /// before this utterance. A set that merely establishes the first recorded
    /// number for an exercise is not.
    private func isGenuinePersonalRecord(_ name: String, before workout: Workout?) -> Bool {
        if knownBestExercises.contains(name) { return true }
        return workout?.entries.contains { entry in
            entry.exercise.name == name && entry.sets.contains { $0.role == .working }
        } ?? false
    }

    /// Exercise names that have at least one completed working set with both a
    /// load and a rep count anywhere in `history` — the exercises for which a
    /// personal record can be beaten. Used to refresh the celebration gate when a
    /// workout ends, so a second workout in the same app session judges records
    /// against up-to-date history (spec story 68).
    static func exercisesWithLoadedWorkingSet(in history: [Workout]) -> Set<String> {
        var names: Set<String> = []
        for workout in history {
            for entry in workout.entries {
                for set in entry.sets where set.role == .working {
                    if set.loadKilograms != nil, set.reps != nil { names.insert(entry.exercise.name) }
                }
            }
        }
        return names
    }

    private func speakReadback(results: [ParseResult]) {
        guard let salient = salientResult(results) else { return }
        let name = exerciseName(for: salient, in: results)
        let style = readbackStyle(
            for: salient,
            isNewExercise: consumeIsNewExercise(for: salient, in: results),
            capAtEarcon: capReadbackAtEarcon
        )
        let plan = readbackPlan(for: salient, style: style, exerciseName: name)
        lastReadback = plan
        readbackVoice.perform(plan)
    }

    private func captureTapSelect(results: [ParseResult]) {
        // Only a non-empty shortlist is a tap-select offer. A low-confidence
        // result with no guesses (e.g. an implausible numeric value) has nothing
        // to tap, so it falls through to `nil` like a clean parse — never `[]`,
        // which `resolveTapSelect`'s `!= nil` guard would wrongly act on.
        for case .lowConfidence(_, let candidates) in results where !candidates.isEmpty {
            tapSelectCandidates = candidates
            return
        }
        // A clean parse resolves any pending disambiguation — including one
        // answered by simply re-speaking the set — so drop the stale list.
        tapSelectCandidates = nil
    }

    /// Keep `activeExerciseName` in step with the engine's active entry. An
    /// `.announcement` moves it (the engine reuses an existing entry for that
    /// name, or appends one); a bare set leaves it where it was; anything that
    /// clears the workout drops it.
    private func updateActiveExercise(from results: [ParseResult]) {
        defer { refreshPreviousWorkoutLine() }
        guard let workout, !workout.isEnded else {
            activeExerciseName = nil
            return
        }
        for case .announcement(let exercise) in results {
            activeExerciseName = exercise.name
            return
        }
        let stillValid = activeExerciseName.map { name in
            workout.entries.contains { $0.exercise.name == name }
        } ?? false
        if !stillValid {
            activeExerciseName = workout.entries.last?.exercise.name
        }
    }

    /// Recompute `previousWorkoutLine` for the current active exercise.
    private func refreshPreviousWorkoutLine() {
        guard let name = activeExerciseName,
              let exercise = library.exercises.first(where: { $0.name == name }) else {
            previousWorkoutLine = nil
            return
        }
        previousWorkoutLine = Self.previousWorkoutLine(
            for: exercise, unit: unit, history: history(), excluding: workout?.startedAt
        )
    }

    /// The formatted "last time" summary for `exercise`, or `nil` when there is
    /// no prior completed workout with a loaded working set for it. The workout
    /// in progress (matched by `openStartedAt`) is filtered out — `history()`
    /// includes it because the engine re-saves it on every set.
    static func previousWorkoutLine(
        for exercise: Exercise, unit: MassUnit, history: [Workout], excluding openStartedAt: Date?
    ) -> String? {
        let prior = history.filter { $0.isEnded && $0.startedAt != openStartedAt }
        guard let last = exerciseProgress(for: exercise, across: prior).sessions.last else { return nil }
        var clauses: [String] = []
        if let top = last.topSetLoadKilograms { clauses.append("top \(loadString(top, unit: unit))") }
        if let e1rm = last.bestEstimatedOneRepMaxKilograms {
            clauses.append("best est. 1RM \(loadString(e1rm, unit: unit))")
        }
        guard !clauses.isEmpty else { return nil }
        return "Last time: " + clauses.joined(separator: " · ")
    }

    // MARK: - Mid-workout editing

    /// Correct the set at `setIndex` of the active entry — the swipe-up list's
    /// row index. Routed through the engine so the live rest target, retry
    /// window, and personal-record bar stay consistent (spec story 38). A no-op
    /// when no entry is active.
    public func editActiveSet(_ setIndex: Int, to set: LoggedSet) {
        guard let entryIndex = activeEntryIndex() else { return }
        engine.editSet(at: entryIndex, setIndex, with: set)
        afterEngineEdit()
    }

    /// Delete the set at `setIndex` of the active entry (spec story 42). A no-op
    /// when no entry is active.
    public func removeActiveSet(_ setIndex: Int) {
        guard let entryIndex = activeEntryIndex() else { return }
        engine.removeSet(at: entryIndex, setIndex)
        afterEngineEdit()
    }

    /// The index of the active entry in `workout.entries` — the last entry whose
    /// exercise name matches `activeExerciseName` (two entries can share a name;
    /// this matches how `HUDProjection` resolves the active entry).
    private func activeEntryIndex() -> Int? {
        guard let name = activeExerciseName else { return nil }
        return workout?.entries.lastIndex { $0.exercise.name == name }
    }

    private func afterEngineEdit() {
        syncFromEngine()
        // re-validate activeExerciseName against the smaller workout; its
        // `defer` refreshes previousWorkoutLine, so no explicit call here.
        updateActiveExercise(from: [])
    }

    private func syncFromEngine() {
        workout = engine.workout
        personalRecords = engine.personalRecords
        restStartedAt = engine.restStartedAt
        restTargetSeconds = engine.currentRestTargetSeconds
        isRestTargetReached = engine.isRestTargetReached
    }

    // MARK: - Small helpers

    private func totalSetCount(_ workout: Workout?) -> Int {
        workout?.entries.reduce(0) { $0 + $1.sets.count } ?? 0
    }

    private func salientResult(_ results: [ParseResult]) -> ParseResult? {
        results.first { isSet($0) }
            ?? results.first { isAnnouncement($0) }
            ?? results.first { isLowConfidence($0) }
    }

    private func exerciseName(for salient: ParseResult, in results: [ParseResult]) -> String? {
        for case .announcement(let exercise) in results { return exercise.name }
        if isAnnouncement(salient), case .announcement(let exercise) = salient { return exercise.name }
        return activeExerciseName
    }

    private func consumeIsNewExercise(for salient: ParseResult, in results: [ParseResult]) -> Bool {
        guard let name = exerciseName(for: salient, in: results) else { return true }
        let isNew = !announcedThisWorkout.contains(name)
        announcedThisWorkout.insert(name)
        return isNew
    }

    /// Replaces the leading name span (everything before the first all-digit
    /// token) with `name`, keeping the numeric tail. "skuat 100 for 5" -> "Squat 100 for 5".
    private func rewrite(_ transcript: String, toName name: String) -> String {
        let tokens = transcript.split(separator: " ").map(String.init)
        // Split at the first clean integer token — the "<load>" or the "<n>" of
        // "<name> <n>". A unit-suffixed or punctuated token ("100kg", "5.") is
        // not a load the parser will accept anyway, so slicing there only yields
        // a transcript that fails to re-parse; keep the predicate strict.
        guard let firstNumber = tokens.firstIndex(where: { Int($0) != nil }) else { return name }
        return ([name] + tokens[firstNumber...]).joined(separator: " ")
    }

    private func isSet(_ r: ParseResult) -> Bool { if case .set = r { return true }; return false }
    private func isAnnouncement(_ r: ParseResult) -> Bool { if case .announcement = r { return true }; return false }
    private func isLowConfidence(_ r: ParseResult) -> Bool { if case .lowConfidence = r { return true }; return false }
    private func isStartWorkout(_ r: ParseResult) -> Bool {
        if case .command(.startWorkout) = r { return true }; return false
    }
}
