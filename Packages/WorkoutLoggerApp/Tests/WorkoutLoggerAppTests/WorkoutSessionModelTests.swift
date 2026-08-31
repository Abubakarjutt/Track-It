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
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(
            store: store, library: Self.library, knownBests: knownBests, now: now
        )
        let source = ScriptedTranscriptSource(script)
        let voice = SpyReadbackVoice()
        let haptics = SpyHaptics()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: voice,
            haptics: haptics, library: Self.library, capReadbackAtEarcon: capAtEarcon, now: now
        )
        return Rig(model: model, source: source, voice: voice, haptics: haptics)
    }

    private func say(_ rig: Rig) async {
        rig.model.pressed()
        await rig.model.released()
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
        // baseline first set is a PR per WorkoutEngine (ADR-0003); haptics are additive by controller ruling — see ledger
        #expect(rig.haptics.played == [.logged, .personalRecord])
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
}
