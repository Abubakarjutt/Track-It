import Testing
import WorkoutLoggerCore

@Suite("Exercise resolver")
struct ResolverTests {

    @Test("an exact name or alias resolves at full confidence")
    func exactMatch() {
        let squat = Exercise(name: "Barbell Back Squat", aliases: ["squat", "squats"])
        let library = ExerciseLibrary([squat])

        #expect(resolve("squats", in: library) == .resolved(squat, confidence: 1.0))
    }

    @Test("a one-character mishear still resolves, below full confidence")
    func editDistanceNearMatch() {
        let pushdown = Exercise(name: "Tricep Pushdown")
        let library = ExerciseLibrary([pushdown])

        guard case .resolved(let exercise, let confidence) =
            resolve("triceps pushdown", in: library)
        else {
            Issue.record("expected .resolved, got \(resolve("triceps pushdown", in: library))")
            return
        }

        #expect(exercise == pushdown)
        #expect(confidence >= 0.85)
        #expect(confidence < 1.0)
    }

    @Test("word order does not matter — token overlap resolves it")
    func tokenSetReorder() {
        let rdl = Exercise(name: "Romanian Deadlift")
        let library = ExerciseLibrary([rdl])

        guard case .resolved(let exercise, _) = resolve("deadlift romanian", in: library) else {
            Issue.record("expected .resolved, got \(resolve("deadlift romanian", in: library))")
            return
        }

        #expect(exercise == rdl)
    }

    @Test("a poor match is unresolved, carrying the closest as a best guess")
    func unresolvedWithGuesses() {
        let row = Exercise(name: "Barbell Row")
        let press = Exercise(name: "Overhead Press")
        let squat = Exercise(name: "Back Squat")
        let curl = Exercise(name: "Bicep Curl")
        let library = ExerciseLibrary([row, press, squat, curl])

        guard case .unresolved(let guesses) = resolve("bicep", in: library) else {
            Issue.record("expected .unresolved, got \(resolve("bicep", in: library))")
            return
        }

        #expect(guesses.count == 3)
        #expect(guesses.first == curl)
    }

    @Test("equal scores break ties deterministically: shorter name first")
    func tieBreak() {
        let barbellRow = Exercise(name: "Barbell Row")
        let cableRow = Exercise(name: "Cable Row")
        let library = ExerciseLibrary([barbellRow, cableRow])

        guard case .unresolved(let guesses) = resolve("row", in: library) else {
            Issue.record("expected .unresolved, got \(resolve("row", in: library))")
            return
        }

        #expect(guesses == [cableRow, barbellRow])
    }
}
