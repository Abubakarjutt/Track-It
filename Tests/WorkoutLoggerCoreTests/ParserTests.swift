import Testing
import WorkoutLoggerCore

@Suite("Parser")
struct ParserTests {

    @Test("'225 for 5' against the active exercise is one working external set")
    func straightWorkingSet() {
        let context = WorkoutContext(
            activeExercise: Exercise(name: "Barbell Bench Press"),
            unit: .pounds
        )

        let results = parse("225 for 5", context: context, library: .empty)

        #expect(results == [
            .set(ParsedSet(
                loadType: .external,
                effort: .reps,
                role: .working,
                grouping: .straight,
                load: 225,
                loadUnit: .pounds,
                reps: 5
            ))
        ])
    }

    @Test("a bare exercise alias is an announcement")
    func announcement() {
        let squat = Exercise(name: "Barbell Back Squat", aliases: ["squat", "squats", "back squat"])
        let library = ExerciseLibrary([squat])

        let results = parse("squats", context: WorkoutContext(), library: library)

        #expect(results == [.announcement(squat)])
    }

    @Test("a 'now' or 'next' lead-in still announces the exercise", arguments: [
        "now squat", "next squat", "now bench", "next bench",
    ])
    func announcementWithLeadIn(phrase: String) {
        let squat = Exercise(name: "Squat", aliases: ["squat"])
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let library = ExerciseLibrary([squat, bench])

        let results = parse(phrase, context: WorkoutContext(), library: library)

        let expected = phrase.hasSuffix("squat") ? squat : bench
        #expect(results == [.announcement(expected)])
    }

    @Test("inline form: an exercise name followed by a set")
    func inlineForm() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"])
        let library = ExerciseLibrary([bench])

        let results = parse(
            "bench 185 for 8",
            context: WorkoutContext(unit: .pounds),
            library: library
        )

        #expect(results == [
            .announcement(bench),
            .set(ParsedSet(
                loadType: .external,
                effort: .reps,
                role: .working,
                grouping: .straight,
                load: 185,
                loadUnit: .pounds,
                reps: 8
            )),
        ])
    }

    @Test("'warmup' marks the set's role")
    func warmupSet() {
        let context = WorkoutContext(
            activeExercise: Exercise(name: "Barbell Bench Press"),
            unit: .pounds
        )

        let results = parse("warmup 135 for 10", context: context, library: .empty)

        #expect(results == [
            .set(ParsedSet(
                loadType: .external,
                effort: .reps,
                role: .warmup,
                grouping: .straight,
                load: 135,
                loadUnit: .pounds,
                reps: 10
            ))
        ])
    }

    @Test("an exercise name and a bare rep count is a bodyweight set")
    func bodyweightSet() {
        let pullUp = Exercise(name: "Pull-Up", aliases: ["pull-ups", "pullups", "pull ups"])
        let library = ExerciseLibrary([pullUp])

        let results = parse("pull-ups 12", context: WorkoutContext(), library: library)

        #expect(results == [
            .announcement(pullUp),
            .set(ParsedSet(
                loadType: .bodyweight,
                effort: .reps,
                role: .working,
                grouping: .straight,
                reps: 12
            )),
        ])
    }

    @Test("'plus <load> for <reps>' is added load on the active exercise")
    func addedLoadSet() {
        let context = WorkoutContext(
            activeExercise: Exercise(name: "Pull-Up"),
            unit: .pounds
        )

        let results = parse("plus 25 for 8", context: context, library: .empty)

        #expect(results == [
            .set(ParsedSet(
                loadType: .added,
                effort: .reps,
                role: .working,
                grouping: .straight,
                load: 25,
                loadUnit: .pounds,
                reps: 8
            ))
        ])
    }

    @Test("'assisted <reps> minus <load>' is an assisted set")
    func assistedSet() {
        let context = WorkoutContext(
            activeExercise: Exercise(name: "Assisted Pull-Up"),
            unit: .pounds
        )

        let results = parse("assisted 8 minus 40", context: context, library: .empty)

        #expect(results == [
            .set(ParsedSet(
                loadType: .assisted,
                effort: .reps,
                role: .working,
                grouping: .straight,
                load: 40,
                loadUnit: .pounds,
                reps: 8
            ))
        ])
    }

    @Test("'<exercise> for <n> seconds' is a duration effort")
    func durationSet() {
        let plank = Exercise(name: "Plank", aliases: ["plank"])
        let library = ExerciseLibrary([plank])

        let results = parse("plank for 60 seconds", context: WorkoutContext(), library: library)

        #expect(results == [
            .announcement(plank),
            .set(ParsedSet(
                loadType: .bodyweight,
                effort: .duration,
                role: .working,
                grouping: .straight,
                durationSeconds: 60
            )),
        ])
    }

    @Test("'undo' is a command")
    func undoCommand() {
        let results = parse("undo", context: WorkoutContext(), library: .empty)

        #expect(results == [.command(.undo)])
    }

    @Test("the fixed command phrases each map to their command", arguments: [
        ("start rest", Command.startRest),
        ("skip rest", .skipRest),
        ("help", .help),
        ("start workout", .startWorkout),
        ("end workout", .endWorkout),
    ])
    func commandPhrases(phrase: String, command: Command) {
        let results = parse(phrase, context: WorkoutContext(), library: .empty)

        #expect(results == [.command(command)])
    }

    @Test("superset markers are commands", arguments: [
        ("superset", Command.startSuperset),
        ("end superset", .endSuperset),
    ])
    func supersetMarkers(phrase: String, command: Command) {
        let results = parse(phrase, context: WorkoutContext(), library: .empty)

        #expect(results == [.command(command)])
    }

    @Test("an explicit spoken unit overrides the context default", arguments: [
        ("100 kilos for 5", MassUnit.kilograms, 100.0),
        ("225 pounds for 5", .pounds, 225.0),
        ("60 kg for 5", .kilograms, 60.0),
    ])
    func explicitSpokenUnit(phrase: String, expectedUnit: MassUnit, expectedLoad: Double) {
        let contextDefault: MassUnit = expectedUnit == .kilograms ? .pounds : .kilograms
        let context = WorkoutContext(
            activeExercise: Exercise(name: "Barbell Bench Press"),
            unit: contextDefault
        )

        let results = parse(phrase, context: context, library: .empty)

        #expect(results == [
            .set(ParsedSet(
                loadType: .external,
                effort: .reps,
                role: .working,
                grouping: .straight,
                load: expectedLoad,
                loadUnit: expectedUnit,
                reps: 5
            ))
        ])
    }

    @Test("an explicit spoken unit is honoured on every keyword load form", arguments: [
        "warmup 60 kg for 10",
        "plus 20 kg for 8",
        "dropset 40 kg for 12",
        "assisted 8 minus 30 kg",
    ])
    func explicitUnitOnKeywordForms(phrase: String) {
        let context = WorkoutContext(
            activeExercise: Exercise(name: "Barbell Bench Press"),
            unit: .pounds // default is pounds; each phrase overrides with kg
        )

        let results = parse(phrase, context: context, library: .empty)

        guard case .set(let set) = results.first else {
            Issue.record("expected a set, got \(results)")
            return
        }
        #expect(set.loadUnit == .kilograms)
    }

    @Test("an explicit spoken unit is honoured on the inline form")
    func explicitUnitOnInlineForm() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let library = ExerciseLibrary([bench])

        let results = parse(
            "bench 100 kg for 5",
            context: WorkoutContext(unit: .pounds),
            library: library
        )

        #expect(results == [
            .announcement(bench),
            .set(ParsedSet(
                loadType: .external,
                effort: .reps,
                role: .working,
                grouping: .straight,
                load: 100,
                loadUnit: .kilograms,
                reps: 5
            )),
        ])
    }

    @Test("an empty or whitespace transcript yields nothing", arguments: ["", "   ", "\n"])
    func emptyTranscript(transcript: String) {
        let results = parse(transcript, context: WorkoutContext(), library: .empty)

        #expect(results.isEmpty)
    }

    @Test("'dropset <load> for <reps>' stamps the grouping axis")
    func dropsetSet() {
        let context = WorkoutContext(
            activeExercise: Exercise(name: "Barbell Curl"),
            unit: .pounds
        )

        let results = parse("dropset 45 for 12", context: context, library: .empty)

        #expect(results == [
            .set(ParsedSet(
                loadType: .external,
                effort: .reps,
                role: .working,
                grouping: .dropset,
                load: 45,
                loadUnit: .pounds,
                reps: 12
            ))
        ])
    }

    @Test("an unrecognised utterance is a low-confidence result")
    func lowConfidenceUnrecognised() {
        let results = parse("flurbo", context: WorkoutContext(), library: .empty)

        #expect(results == [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: [])])
    }

    @Test("a low-confidence result carries the ranked candidate exercises as a list")
    func lowConfidenceCarriesGuessList() {
        let row = Exercise(name: "Barbell Row")
        let curl = Exercise(name: "Bicep Curl")
        let press = Exercise(name: "Overhead Press")
        let library = ExerciseLibrary([row, curl, press])

        let results = parse("bicep", context: WorkoutContext(), library: library)

        #expect(results == [
            .lowConfidence(reason: .unrecognisedExercise, bestGuesses: [curl, row, press])
        ])
    }

    @Test("a bare rep count too large to be real reps is flagged, not logged")
    func bodyweightSetImplausibleRepCount() {
        // "bench 225" is a dropped-"for" mis-hear (225 for N), not a 225-rep
        // bodyweight set. The parser should not fabricate the set.
        let bench = Exercise(name: "Bench Press", aliases: ["bench"])
        let library = ExerciseLibrary([bench])

        let results = parse("bench 225", context: WorkoutContext(), library: library)

        #expect(results == [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: [bench])])
    }

    @Test("a 'for <n>' set with an implausible rep count is flagged, not logged")
    func implausibleRepCountIsFlagged() {
        // "100 for 500" is a mis-hear of the rep slot, not a 500-rep set.
        let results = parse("100 for 500", context: WorkoutContext(), library: .empty)

        #expect(results == [.lowConfidence(reason: .implausibleValue, bestGuesses: [])])
    }

    @Test("a set with an implausible load is flagged, not logged")
    func implausibleLoadIsFlagged() {
        // "5000" is a magnitude mis-hear (five hundred → five thousand), not a real load.
        let squat = Exercise(name: "Squat", aliases: ["squat"])
        let library = ExerciseLibrary([squat])

        let results = parse("squat 5000 for 5", context: WorkoutContext(), library: library)

        #expect(results == [.lowConfidence(reason: .implausibleValue, bestGuesses: [squat])])
    }

    @Test("an inline set whose exercise only weakly matches is low-confidence, not a logged set")
    func inlineSetWeakMatchIsNotLogged() {
        // "squuat" scores ~0.83 against "Squat" — resolvable, but below the bar
        // to auto-log a set against. The parser should surface the doubt and log
        // nothing rather than emit a confident-looking set the engine will keep.
        let squat = Exercise(name: "Squat")
        let library = ExerciseLibrary([squat])

        let results = parse(
            "squuat 100 for 5",
            context: WorkoutContext(unit: .pounds),
            library: library
        )

        #expect(results == [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: [squat])])
    }

    @Test("'<exercise> <n> meters' is a distance effort")
    func distanceSet() {
        let carry = Exercise(name: "Farmer's Carry", aliases: ["farmer carry", "farmers carry"])
        let library = ExerciseLibrary([carry])

        let results = parse("farmer carry 40 meters", context: WorkoutContext(), library: library)

        #expect(results == [
            .announcement(carry),
            .set(ParsedSet(
                loadType: .bodyweight,
                effort: .distance,
                role: .working,
                grouping: .straight,
                distanceMeters: 40
            )),
        ])
    }
}
