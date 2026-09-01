import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutSessionModel")
@MainActor
struct WorkoutSessionModelTests {

    private static let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    private static let library = ExerciseLibrary([bench])

    private struct Rig {
        let model: WorkoutSessionModel
        let source: ScriptedTranscriptSource
        let voice: SpyReadbackVoice
        let haptics: SpyHaptics
    }

    private func makeRig(
        script: [[String]],
        capAtEarcon: Bool = false,
        knownBests: [String: Double] = [:],
        knownBestExercises: Set<String>? = nil,
        unit: MassUnit = .kilograms,
        history: @escaping () -> [Workout] = { [] },
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(
            store: store, library: Self.library, unit: unit, knownBests: knownBests, now: now
        )
        let source = ScriptedTranscriptSource(script)
        let voice = SpyReadbackVoice()
        let haptics = SpyHaptics()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: voice,
            haptics: haptics, library: Self.library, unit: unit,
            capReadbackAtEarcon: capAtEarcon, now: now,
            knownBestExercises: knownBestExercises ?? Set(knownBests.keys),
            history: history
        )
        return Rig(model: model, source: source, voice: voice, haptics: haptics)
    }

    private func say(_ rig: Rig) async {
        rig.model.pressed()
        await rig.model.released()
    }

    private func makeMultiExerciseModel(
        script: [[String]],
        exercises: [Exercise],
        knownBestExercises: Set<String> = [],
        history: (() -> [Workout])? = nil
    ) throws -> (model: WorkoutSessionModel, store: SwiftDataWorkoutStore, haptics: SpyHaptics) {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let library = ExerciseLibrary(exercises)
        let engine = WorkoutEngine(store: store, library: library)
        let haptics = SpyHaptics()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource(script),
            readbackVoice: SpyReadbackVoice(), haptics: haptics, library: library,
            knownBestExercises: knownBestExercises,
            // Default: history reads this helper's own store, so a scripted
            // "end workout" is visible to the celebration-gate re-derive.
            history: history ?? { store.history() }
        )
        return (model, store, haptics)
    }

    @Test("a start-workout utterance opens a workout")
    func startsWorkout() async throws {
        let rig = try makeRig(script: [["start workout"]])
        await say(rig)
        #expect(rig.model.workout != nil)
        #expect(rig.model.workout?.isEnded == false)
    }

    @Test("a spoken set is logged, fires the logged haptic, and reads back full the first time")
    func firstSet() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
        await say(rig) // start
        await say(rig) // bench 100 for 5

        #expect(rig.model.workout?.entries.first?.exercise == Self.bench)
        #expect(rig.model.workout?.entries.first?.sets.count == 1)
        // A baseline-setting first working set logs but does not celebrate: the
        // engine emits a PersonalRecord for it (ADR-0003), but the model's
        // genuine-PR gate suppresses the .personalRecord haptic because the
        // exercise had no seeded best and no earlier working set this workout.
        #expect(rig.haptics.played == [.logged])
        #expect(rig.model.lastReadback == .speak("Logged. Bench Press, 100 kilograms for 5 reps."))
    }

    @Test("the second set of the same exercise reads back terse")
    func secondSetTerse() async throws {
        let rig = try makeRig(script: [
            ["start workout"], ["bench 100 for 5"], ["bench 100 for 5"],
        ])
        await say(rig); await say(rig); await say(rig)

        #expect(rig.model.workout?.entries.first?.sets.count == 2)
        #expect(rig.model.lastReadback == .speak("100 for 5"))
    }

    @Test("capReadbackAtEarcon makes every readback an earcon")
    func earconCap() async throws {
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]], capAtEarcon: true
        )
        await say(rig); await say(rig)
        #expect(rig.model.lastReadback == .earcon)
    }

    @Test("released() resets isListening even when the source throws")
    func throwingSourceResetsListening() async throws {
        let rig = try makeRig(script: [])
        rig.source.throwWhenExhausted = true
        rig.model.pressed()
        #expect(rig.model.isListening == true)
        await rig.model.released()
        #expect(rig.model.isListening == false)
        #expect(rig.model.workout == nil)
        // A thrown speech path must still be perceptible on an eyes-free app.
        #expect(rig.haptics.played.contains(.notCaught))
        #expect(rig.voice.performed.contains(.earcon))
    }

    @Test("an unparseable utterance fires notCaught, offers candidates, logs nothing")
    func parseFailure() async throws {
        let rig = try makeRig(script: [["start workout"], ["flurbo"]])
        await say(rig); await say(rig)

        #expect(rig.haptics.played.contains(.notCaught))
        #expect(rig.model.tapSelectCandidates != nil)
        #expect(rig.model.workout?.entries.isEmpty == true)
    }

    @Test("resolveTapSelect logs the set against the chosen exercise and clears candidates")
    func tapSelectResolution() async throws {
        // Fixture depends on core's (private) fuzzy matcher landing "bench bruss" in the
        // low-confidence band: editSimilarity("bench bruss","bench press") ≈ 0.818
        // (Levenshtein 2 / max length 11). It must stay: ≥ resolveThreshold (0.60) so a
        // candidate surfaces, < confidentMatchThreshold (0.85) so it isn't auto-logged, and
        // < 0.85 so PostProcessor.biasExerciseName leaves the spoken name alone. A
        // behaviour-preserving change to levenshtein or those constants will break this test.
        let rig = try makeRig(script: [["start workout"], ["bench bruss 100 for 5"]])
        await say(rig); await say(rig)
        try #require(rig.model.tapSelectCandidates?.isEmpty == false)

        rig.model.resolveTapSelect(Self.bench)

        #expect(rig.model.tapSelectCandidates == nil)
        #expect(rig.model.workout?.entries.count == 1)
        #expect(rig.model.workout?.entries.first?.exercise == Self.bench)
        #expect(rig.model.workout?.entries.first?.sets.first?.reps == 5)
    }

    @Test("a low-confidence result with no best guesses leaves the selection nil, not []")
    func lowConfidenceWithoutCandidatesLeavesNilSelection() async throws {
        // "100000 for 5" parses as a straight set whose load is implausible, so
        // the parser returns `.lowConfidence(.implausibleValue, bestGuesses: [])`.
        let rig = try makeRig(script: [["start workout"], ["100000 for 5"]])
        await say(rig); await say(rig)

        #expect(rig.model.tapSelectCandidates == nil)
        #expect(rig.haptics.played.contains(.notCaught))
        #expect(rig.model.workout?.entries.isEmpty == true)
    }

    @Test("resolveTapSelect slices the rewrite at the first clean integer token")
    func rewriteSlicesAtFirstIntegerToken() async throws {
        // The stored transcript here has a unit-suffixed leading numeric token
        // ("100kg"). `rewrite` must split at the first *clean integer* ("5"), so
        // the chosen exercise still logs a set. Widening the split predicate to
        // any digit-bearing token would slice at "100kg", producing
        // "Bench Press 100kg for 5" — which the parser rejects, logging nothing.
        let rig = try makeRig(script: [["start workout"], ["bench bruss 100kg for 5"]])
        await say(rig); await say(rig)
        try #require(rig.model.tapSelectCandidates?.isEmpty == false)

        rig.model.resolveTapSelect(Self.bench)

        #expect(rig.model.tapSelectCandidates == nil)
        #expect(rig.model.workout?.entries.count == 1)
        #expect(rig.model.workout?.entries.first?.exercise == Self.bench)
        #expect(rig.model.workout?.entries.first?.sets.first?.reps == 5)
    }

    @Test("a set that beats the known best fires the personalRecord haptic")
    func personalRecord() async throws {
        // knownBests below the e1RM of 100x5 (Epley: 100 * 35 / 30 = 116.67)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            knownBests: ["Bench Press": 100]
        )
        await say(rig); await say(rig)

        #expect(rig.haptics.played.contains(.personalRecord))
        #expect(rig.model.personalRecords.count == 1)
    }

    @Test("a personal-record set fires the logged tap then the PR celebration")
    func prAddsToLoggedHaptic() async throws {
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            knownBests: ["Bench Press": 100]
        )
        await say(rig); await say(rig)
        #expect(rig.haptics.played == [.logged, .personalRecord])
    }

    @Test("a clean utterance after a low-confidence one clears the candidate list")
    func cleanUtteranceClearsCandidates() async throws {
        let rig = try makeRig(script: [["start workout"], ["flurbo"], ["bench 100 for 5"]])
        await say(rig); await say(rig)
        try #require(rig.model.tapSelectCandidates != nil)
        await say(rig)
        #expect(rig.model.tapSelectCandidates == nil)
    }

    @Test("dismissTapSelect drops the candidate list without touching the workout")
    func dismissTapSelectClearsWithoutLogging() async throws {
        let rig = try makeRig(script: [["start workout"], ["flurbo"]])
        await say(rig); await say(rig)
        try #require(rig.model.tapSelectCandidates != nil)
        let before = rig.model.workout

        rig.model.dismissTapSelect()

        #expect(rig.model.tapSelectCandidates == nil)
        #expect(rig.model.workout == before)
    }

    @Test("tick fires restReached once after the rest target passes, then not again")
    func restReachedOnce() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            now: { clock }
        )
        await say(rig) // start (clock 1000)
        await say(rig) // set logged — rest starts at 1000, default target 120s
        #expect(rig.model.restElapsed == 0) // fresh rest period, not last set's stale value

        clock = Date(timeIntervalSince1970: 1_030) // 30s elapsed
        rig.model.tick()
        #expect(rig.model.restElapsed == 30)
        #expect(rig.haptics.played.contains(.restReached) == false)

        clock = Date(timeIntervalSince1970: 1_125) // 125s elapsed, past 120
        rig.model.tick()
        rig.model.tick() // second tick must not re-fire
        #expect(rig.haptics.played.filter { $0 == .restReached }.count == 1)
    }

    @Test("a new set resets the rest-reached latch")
    func latchResetsPerSet() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"], ["bench 100 for 5"]],
            now: { clock }
        )
        await say(rig) // start
        await say(rig) // set 1, rest starts 1000

        clock = Date(timeIntervalSince1970: 1_130)
        rig.model.tick() // fires restReached (1st)

        await say(rig) // set 2, rest restarts at 1130, latch cleared
        clock = Date(timeIntervalSince1970: 1_260) // 130s after 1130
        rig.model.tick() // fires restReached (2nd)

        #expect(rig.haptics.played.filter { $0 == .restReached }.count == 2)
    }

    @Test("displayUnit surfaces the injected unit")
    func displayUnitSurfacesInjectedUnit() throws {
        #expect(try makeRig(script: []).model.displayUnit == .kilograms)
        #expect(try makeRig(script: [], unit: .pounds).model.displayUnit == .pounds)
    }

    @Test("keepScreenAwake is true only while a workout is open")
    func keepScreenAwakeReflectsOpenWorkout() async throws {
        let rig = try makeRig(script: [["start workout"], ["end workout"]])
        #expect(rig.model.keepScreenAwake == false)
        await say(rig)
        #expect(rig.model.keepScreenAwake == true)
        await say(rig)
        #expect(rig.model.keepScreenAwake == false)
    }

    @Test("restTargetSeconds and isRestTargetReached track the engine")
    func restTargetFieldsTrackEngine() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]], now: { clock }
        )
        await say(rig); await say(rig)
        #expect(rig.model.restTargetSeconds == 120)
        #expect(rig.model.isRestTargetReached == false)

        clock = Date(timeIntervalSince1970: 1_200) // 200s > 120
        rig.model.tick()
        #expect(rig.model.isRestTargetReached == true)
    }

    @Test("a baseline first set is silent on PR, but beating your own opener later celebrates")
    func genuinePRGate() async throws {
        let rig = try makeRig(script: [
            ["start workout"], ["bench 60 for 5"], ["bench 120 for 5"],
        ])
        await say(rig)                    // start
        await say(rig)                    // 60x5 — baseline, no seeded best
        #expect(rig.haptics.played == [.logged])

        await say(rig)                    // 120x5 — beats the in-workout best
        #expect(rig.haptics.played == [.logged, .logged, .personalRecord])
    }

    @Test("a seeded exercise fires the PR haptic on the very first set that beats it")
    func seededExerciseCelebratesFirstSet() async throws {
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            knownBests: ["Bench Press": 50]
        )
        await say(rig); await say(rig)
        #expect(rig.haptics.played == [.logged, .personalRecord])
    }

    @Test("resuming a workout seeds announced exercises so their next readback is terse")
    func resumeSeedsAnnouncedExercises() async throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let now = { Date(timeIntervalSince1970: 5_000) }
        let engine = WorkoutEngine(store: store, library: Self.library, now: now)
        let prior = Workout(
            entries: [Entry(exercise: Self.bench, sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10)),
            ])],
            startedAt: Date(timeIntervalSince1970: 10)
        )
        engine.resume(prior)

        let source = ScriptedTranscriptSource([["bench 100 for 5"]])
        let voice = SpyReadbackVoice()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: voice,
            haptics: SpyHaptics(), library: Self.library, now: now
        )

        model.pressed(); await model.released()

        // Bench was already in the resumed workout, so it is not "new this
        // workout" — readback is terse, not the full "Logged. Bench Press, ...".
        #expect(model.lastReadback == .speak("100 for 5"))
    }

    @Test("pendingStaleWorkout resolves via resume")
    func staleRecoveryResume() async throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library)
        let stale = Workout(
            entries: [Entry(exercise: Self.bench, sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10)),
            ])],
            startedAt: Date(timeIntervalSince1970: 10)
        )
        var resumed = false
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource([]),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: Self.library,
            staleRecovery: .init(
                workout: stale,
                onResume: { resumed = true; engine.resume(stale) },
                onDiscard: { }
            )
        )

        #expect(model.pendingStaleWorkout == stale)
        model.resumePendingStaleWorkout()

        #expect(resumed)
        #expect(model.pendingStaleWorkout == nil)
        #expect(model.workout?.entries.first?.exercise == Self.bench)
    }

    @Test("pendingStaleWorkout resolves via discard without adopting the workout")
    func staleRecoveryDiscard() async throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library)
        let stale = Workout(
            entries: [Entry(exercise: Self.bench, sets: [])],
            startedAt: Date(timeIntervalSince1970: 10)
        )
        var discarded = false
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource([]),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: Self.library,
            staleRecovery: .init(workout: stale, onResume: { }, onDiscard: { discarded = true })
        )

        model.discardPendingStaleWorkout()

        #expect(discarded)
        #expect(model.pendingStaleWorkout == nil)
        #expect(model.workout == nil)   // engine never adopted it
    }

    @Test("previousWorkoutLine shows the last completed workout's top set and best estimate for the active exercise")
    func previousWorkoutLineForActiveExercise() async throws {
        let priorBench = Workout(
            entries: [Entry(exercise: Self.bench, sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10)),
            ])],
            startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 70)
        )
        let rig = try makeRig(
            script: [["start workout"], ["bench 90 for 5"]],
            history: { [priorBench] }
        )
        await say(rig)   // start
        await say(rig)   // bench 90 for 5 — active exercise becomes Bench

        // e1RM(100,5) = 100 * 35 / 30 = 116.666… -> gymRound 116.7
        #expect(rig.model.previousWorkoutLine == "Last time: top 100 kg · best e1RM 116.7 kg")
    }

    @Test("previousWorkoutLine is nil for an exercise with no prior history")
    func previousWorkoutLineNilForNewExercise() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]], history: { [] })
        await say(rig); await say(rig)
        #expect(rig.model.previousWorkoutLine == nil)
    }

    @Test("previousWorkoutLine ignores the workout currently in progress")
    func previousWorkoutLineExcludesOpenWorkout() async throws {
        // history() returns the open workout too — the engine re-saves it on every
        // set — so the filter must drop the workout whose startedAt matches the open
        // one. This test builds its own store so history() reads real saved state.
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library)
        let model = WorkoutSessionModel(
            engine: engine,
            transcriptSource: ScriptedTranscriptSource([
                ["start workout"], ["bench 100 for 5"], ["bench 105 for 5"],
            ]),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: Self.library,
            history: { store.history() }
        )
        for _ in 0..<3 { model.pressed(); await model.released() }

        #expect(model.previousWorkoutLine == nil)  // the only stored workout is the open one
    }

    @Test("editActiveSet routes a corrected set through the engine and updates the projection")
    func editActiveSetUpdatesLiveWorkout() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
        await say(rig); await say(rig)

        rig.model.editActiveSet(0, to: LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 105, reps: 5, loggedAt: Date(timeIntervalSince1970: 0)
        ))

        #expect(rig.model.workout?.entries[0].sets[0].loadKilograms == 105)
    }

    @Test("removeActiveSet deletes the row and, when it empties the entry, moves the active exercise")
    func removeActiveSetEmptiesEntry() async throws {
        let bench = Exercise(name: "Bench Press", aliases: ["bench"])
        let squat = Exercise(name: "Back Squat", aliases: ["squat"])
        let (model, _, _) = try makeMultiExerciseModel(
            script: [["start workout"], ["bench 100 for 5"], ["squat 140 for 5"], ["bench"]],
            exercises: [bench, squat]
        )
        for _ in 0..<4 { model.pressed(); await model.released() }
        // Active exercise is Bench again, its entry has exactly one set.

        model.removeActiveSet(0)

        #expect(model.workout?.entries.map { $0.exercise.name } == ["Back Squat"])
        #expect(model.activeExerciseName == "Back Squat")
    }

    @Test("the edit wrappers are a no-op when no workout is open")
    func editWrappersNoOpWithoutWorkout() throws {
        let rig = try makeRig(script: [])
        rig.model.editActiveSet(0, to: LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 1, reps: 1, loggedAt: Date(timeIntervalSince1970: 0)
        ))
        rig.model.removeActiveSet(0)
        #expect(rig.model.workout == nil)
    }

    @Test("a bare set after returning to an earlier exercise still reads back terse")
    func bareSetReadbackAfterReturnIsStable() async throws {
        let bench = Exercise(name: "Bench Press", aliases: ["bench"])
        let squat = Exercise(name: "Back Squat", aliases: ["squat"])
        let (model, _, _) = try makeMultiExerciseModel(
            script: [
                ["start workout"], ["bench 100 for 5"], ["squat 140 for 3"], ["bench"], ["100 for 5"],
            ],
            exercises: [bench, squat]
        )
        for _ in 0..<5 { model.pressed(); await model.released() }

        // Characterization: the last utterance is a bare set on the re-announced Bench
        // entry. It must land on Bench (activeExerciseName), and the readback is terse.
        #expect(model.activeExerciseName == "Bench Press")
        #expect(model.workout?.entries.map { $0.exercise.name } == ["Bench Press", "Back Squat"])
        #expect(model.workout?.entries[0].sets.count == 2)   // the bare set went to Bench, not Squat
        #expect(model.lastReadback == .speak("100 for 5"))
    }

    @Test("a second same-session workout celebrates a set that beats the ended workout's best")
    func secondWorkoutCelebratesAgainstEndedWorkout() async throws {
        let bench = Exercise(name: "Bench Press", aliases: ["bench"])
        let (model, _, haptics) = try makeMultiExerciseModel(
            script: [
                ["start workout"], ["bench 100 for 5"], ["end workout"],
                ["start workout"], ["bench 120 for 5"],
            ],
            exercises: [bench],
            knownBestExercises: []                 // nothing seeded at launch
        )

        for _ in 0..<5 { model.pressed(); await model.released() }

        // First workout's 100×5 is e1RM 116.7 — logged, not celebrated (first ever).
        // "end workout" re-derives the gate from history (wired to the helper's store
        // by default), so "Bench Press" now counts as an exercise with a beatable
        // record. The second workout's 120×5 (e1RM 140) beats it, so the
        // personal-record haptic fires.
        #expect(haptics.played.contains(.personalRecord))
    }
}
