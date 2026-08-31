import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("Readback composer")
struct ReadbackComposerTests {

    private func repsSet(load: Double?, unit: MassUnit? = .kilograms, reps: Int) -> ParseResult {
        .set(ParsedSet(
            loadType: load == nil ? .bodyweight : .external,
            effort: .reps, role: .working, grouping: .straight,
            load: load, loadUnit: load == nil ? nil : unit, reps: reps
        ))
    }

    @Test("full readback of a loaded set names the exercise and spells it out")
    func fullLoaded() {
        let plan = readbackPlan(
            for: repsSet(load: 100, reps: 5), style: .full, exerciseName: "Bench Press"
        )
        #expect(plan == .speak("Logged. Bench Press, 100 kilograms for 5 reps."))
    }

    @Test("terse readback of a loaded set is just the numbers")
    func terseLoaded() {
        let plan = readbackPlan(for: repsSet(load: 100, reps: 5), style: .terse, exerciseName: nil)
        #expect(plan == .speak("100 for 5"))
    }

    @Test("a spoken pounds unit is read back in pounds")
    func poundsUnit() {
        let plan = readbackPlan(
            for: repsSet(load: 225, unit: .pounds, reps: 3), style: .full, exerciseName: "Squat"
        )
        #expect(plan == .speak("Logged. Squat, 225 pounds for 3 reps."))
    }

    @Test("a fractional load keeps its decimal")
    func fractionalLoad() {
        let plan = readbackPlan(
            for: repsSet(load: 102.5, reps: 2), style: .terse, exerciseName: nil
        )
        #expect(plan == .speak("102.5 for 2"))
    }

    @Test("terse readback of a bodyweight set")
    func terseBodyweight() {
        let plan = readbackPlan(for: repsSet(load: nil, reps: 12), style: .terse, exerciseName: nil)
        #expect(plan == .speak("12 reps"))
    }

    @Test("full readback of a duration set")
    func fullDuration() {
        let set = ParseResult.set(ParsedSet(
            loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
            durationSeconds: 60
        ))
        #expect(readbackPlan(for: set, style: .full, exerciseName: "Plank") == .speak("Logged. Plank, 60 seconds."))
    }

    @Test("an announcement reads the exercise name")
    func announcement() {
        let plan = readbackPlan(
            for: .announcement(Exercise(name: "Deadlift")), style: .full, exerciseName: nil
        )
        #expect(plan == .speak("Deadlift."))
    }

    @Test("a low-confidence result asks for a repeat")
    func lowConfidence() {
        let plan = readbackPlan(
            for: .lowConfidence(reason: .unrecognisedExercise, bestGuesses: []),
            style: .full, exerciseName: nil
        )
        #expect(plan == .speak("Didn't catch that."))
    }

    @Test("earcon style always yields an earcon")
    func earconStyle() {
        #expect(readbackPlan(for: repsSet(load: 100, reps: 5), style: .earcon, exerciseName: "X") == .earcon)
    }

    @Test("a command yields an earcon")
    func command() {
        #expect(readbackPlan(for: .command(.undo), style: .terse, exerciseName: nil) == .earcon)
    }
}
