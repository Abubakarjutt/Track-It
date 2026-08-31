import Testing
import WorkoutLoggerCore

@Suite("STT post-processor")
struct PostProcessorTests {

    @Test("a clean transcript that needs no correction is returned unchanged")
    func passthrough() {
        let result = postProcess(["225 for 5"], library: .empty)

        #expect(result == "225 for 5")
    }

    @Test("a single number word in a numeric slot becomes a digit", arguments: [
        ("pull ups twelve", "pull ups 12"),
        ("plank for sixty seconds", "plank for 60 seconds"),
        ("squat five", "squat 5"),
    ])
    func singleNumberWord(spoken: String, expected: String) {
        #expect(postProcess([spoken], library: .empty) == expected)
    }

    @Test("compound spoken numbers collapse to one digit string", arguments: [
        ("squat two twenty five for five", "squat 225 for 5"),
        ("bench one thirty five for eight", "bench 135 for 8"),
        ("curl twenty five for twelve", "curl 25 for 12"),
        ("deadlift one oh five for three", "deadlift 105 for 3"),
        ("press one hundred for five", "press 100 for 5"),
    ])
    func compoundNumberWords(spoken: String, expected: String) {
        #expect(postProcess([spoken], library: .empty) == expected)
    }

    @Test("a misheard exercise-name span is biased toward the library", arguments: [
        ("romanian deadlif 315 for 3", "romanian deadlift 315 for 3"), // repaired
        ("romanian deadlift 315 for 3", "romanian deadlift 315 for 3"), // exact — left alone
        ("incline press 185 for 6", "incline press 185 for 6"),         // not in library — left alone
    ])
    func exerciseNameBiasing(spoken: String, expected: String) {
        let library = ExerciseLibrary([Exercise(name: "Romanian Deadlift", aliases: ["rdl"])])

        #expect(postProcess([spoken], library: library) == expected)
    }

    @Test("the hypothesis whose exercise name best matches the library is chosen")
    func picksBestResolvingHypothesis() {
        let library = ExerciseLibrary([Exercise(name: "Bench Press", aliases: ["bench press"])])

        let result = postProcess(
            ["bench breast 225 for 5", "bench press 225 for 5"],
            library: library
        )

        #expect(result == "bench press 225 for 5")
    }

    @Test("a number word that belongs to an exercise name is not turned into a digit")
    func numberWordInsideExerciseName() {
        let library = ExerciseLibrary([Exercise(name: "One-Arm Row", aliases: ["one arm row"])])

        let result = postProcess(["one arm row 135 for 8"], library: library)

        #expect(result == "one arm row 135 for 8")
    }
}
