import Testing
import WorkoutLoggerCore

@Suite("Readback")
struct ReadbackTests {

    private let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    private func set(confidence: Double = 1.0) -> ParseResult {
        .set(ParsedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            load: 100, loadUnit: .kilograms, reps: 5
        ), confidence: confidence)
    }

    @Test("a set for a familiar exercise gets a terse readback")
    func terseForAFamiliarExercise() {
        #expect(
            readbackStyle(for: set(), isNewExercise: false, capAtEarcon: false)
                == .terse
        )
    }

    @Test("a new exercise this workout forces a full readback")
    func fullWhenExerciseIsNew() {
        #expect(
            readbackStyle(for: .announcement(bench, confidence: 1.0), isNewExercise: true, capAtEarcon: false)
                == .full
        )
    }

    @Test("a low-confidence parse result is always read back in full")
    func fullForLowConfidenceResult() {
        #expect(
            readbackStyle(
                for: .lowConfidence(reason: .unrecognisedExercise, bestGuesses: []),
                isNewExercise: false, capAtEarcon: false
            ) == .full
        )
    }

    @Test("a shaky parse of a familiar exercise still gets a full readback")
    func fullForLowConfidenceKnownExercise() {
        #expect(
            readbackStyle(for: set(confidence: 0.7), isNewExercise: false, capAtEarcon: false)
                == .full
        )
    }

    @Test("the earcon-only setting overrides everything")
    func earconCapWins() {
        #expect(
            readbackStyle(
                for: .lowConfidence(reason: .unrecognisedExercise, bestGuesses: []),
                isNewExercise: true, capAtEarcon: true
            ) == .earcon
        )
    }

    @Test("a bare command just gets an earcon acknowledgement")
    func earconForCommands() {
        #expect(
            readbackStyle(for: .command(.undo), isNewExercise: false, capAtEarcon: false)
                == .earcon
        )
    }
}
