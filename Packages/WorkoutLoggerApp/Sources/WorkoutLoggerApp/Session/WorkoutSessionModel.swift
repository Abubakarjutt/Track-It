import Foundation
import Observation
import WorkoutLoggerCore

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

    @ObservationIgnored private let engine: WorkoutEngine
    @ObservationIgnored private let transcriptSource: TranscriptSource
    @ObservationIgnored private let readbackVoice: ReadbackVoice
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private let library: ExerciseLibrary
    @ObservationIgnored private let unit: MassUnit
    @ObservationIgnored private let capReadbackAtEarcon: Bool
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var announcedThisWorkout: Set<String> = []
    @ObservationIgnored private var lastTranscript = ""
    @ObservationIgnored private var restReachedFired = false

    public init(
        engine: WorkoutEngine,
        transcriptSource: TranscriptSource,
        readbackVoice: ReadbackVoice,
        haptics: Haptics,
        library: ExerciseLibrary,
        unit: MassUnit = .kilograms,
        capReadbackAtEarcon: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.engine = engine
        self.transcriptSource = transcriptSource
        self.readbackVoice = readbackVoice
        self.haptics = haptics
        self.library = library
        self.unit = unit
        self.capReadbackAtEarcon = capReadbackAtEarcon
        self.now = now
        syncFromEngine()
    }

    /// The unit the HUD formats loads in — the injected preference.
    public var displayUnit: MassUnit { unit }

    /// True while a workout is open; the view maps it to `isIdleTimerDisabled`.
    public var keepScreenAwake: Bool {
        guard let workout else { return false }
        return !workout.isEnded
    }

    public func pressed() {
        transcriptSource.beginUtterance()
        isListening = true
    }

    public func released() async {
        isListening = false
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

        engine.hear(hypotheses)
        syncFromEngine()

        let setsAfter = totalSetCount(workout)
        let loggedASet = setsAfter > setsBefore

        fireHaptic(results: results, loggedASet: loggedASet, prGrew: engine.personalRecords.count > prBefore)
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

    private func fireHaptic(results: [ParseResult], loggedASet: Bool, prGrew: Bool) {
        // Additive by controller ruling: every logged set taps `.logged`; a PR
        // adds `.personalRecord` on top. The brief's mutually-exclusive form
        // can't pass `firstSet` because the engine emits a PersonalRecord even
        // for a baseline-setting first set.
        if loggedASet {
            haptics.play(.logged)
            if prGrew { haptics.play(.personalRecord) }
            return
        }
        if results.contains(where: { isLowConfidence($0) }) {
            haptics.play(.notCaught)
        }
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
        return workout?.entries.last?.exercise.name
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
