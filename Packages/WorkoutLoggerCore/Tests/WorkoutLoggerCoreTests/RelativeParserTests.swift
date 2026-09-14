import Testing
import WorkoutLoggerCore

// Cluster 7d — the relative / contextual grammar forms that lean on
// `context.previousSet` (the seam cluster 1b built but the parser never
// consumed). Each form is deterministic given the previous set, so it reports
// full confidence and fails closed when there is no previous set.

@Suite("Relative forms")
struct RelativeParserTests {

    private let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"])
    private var library: ExerciseLibrary { ExerciseLibrary([bench]) }

    private func context(
        _ previous: ParsedSet?,
        active: Exercise = Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"]),
        unit: MassUnit = .kilograms
    ) -> WorkoutContext {
        WorkoutContext(activeExercise: active, previousSet: previous, unit: unit)
    }

    private func workingLoad(_ load: Double, reps: Int, unit: MassUnit = .kilograms) -> ParsedSet {
        ParsedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            load: load, loadUnit: unit, reps: reps
        )
    }

    private func load(of results: [ParseResult]) -> (load: Double?, unit: MassUnit?, reps: Int?)? {
        guard case let .set(set, _) = results.first else { return nil }
        return (set.load, set.loadUnit, set.reps)
    }

    // MARK: - Repeat the previous set

    @Test("an exact repeat phrase (incl. a bare 'one more') reproduces the previous set",
          arguments: [
        "again", "repeat", "same", "same again", "same as last time", "same as last",
        "one more",
    ])
    func repeatPreviousSet(phrase: String) {
        let previous = workingLoad(100, reps: 5)
        let results = parse(phrase, context: context(previous), library: library)
        #expect(results == [.set(previous, confidence: 1.0)])
    }

    @Test("a verbatim repeat phrase repeats a loadless set too", arguments: ["again", "one more"])
    func repeatsLoadlessSet(phrase: String) {
        let previous = ParsedSet(
            loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
            durationSeconds: 60
        )
        let results = parse(phrase, context: context(previous), library: library)
        #expect(results == [.set(previous, confidence: 1.0)])
    }

    // MARK: - Plate steps (one standard plate per unit — see ADR-0004)

    @Test("'add a plate' adds one plate to the previous load, in each unit")
    func addAPlate() {
        // kg: 100 + 20 = 120.
        #expect(
            load(of: parse("add a plate", context: context(workingLoad(100, reps: 5, unit: .kilograms), unit: .kilograms), library: library))?
                .load == 120
        )
        // lb: 100 + 45 = 145.
        #expect(
            load(of: parse("add a plate", context: context(workingLoad(100, reps: 5, unit: .pounds), unit: .pounds), library: library))?
                .load == 145
        )
    }

    @Test("'drop a plate' removes one plate in each unit")
    func dropAPlate() {
        // kg: 100 - 20 = 80.
        #expect(
            load(of: parse("drop a plate", context: context(workingLoad(100, reps: 5, unit: .kilograms), unit: .kilograms), library: library))?
                .load == 80
        )
        // lb: 100 - 45 = 55.
        #expect(
            load(of: parse("drop a plate", context: context(workingLoad(100, reps: 5, unit: .pounds), unit: .pounds), library: library))?
                .load == 55
        )
    }

    @Test("a load delta never drops the load below zero")
    func loadDeltaFloorsAtZero() {
        let previous = workingLoad(5, reps: 5)
        let results = parse("down 10", context: context(previous), library: library)
        #expect(load(of: results)?.load == 0)
    }

    // MARK: - Numeric load delta in the context unit

    @Test("'up N' / 'add N' / 'plus N' raise the previous load by N", arguments: [
        "up 10", "add 10", "plus 10",
    ])
    func raiseLoad(phrase: String) {
        let previous = workingLoad(100, reps: 5)
        let results = parse(phrase, context: context(previous), library: library)
        #expect(load(of: results)?.load == 110)
        #expect(load(of: results)?.reps == 5)
    }

    @Test("'down N' / 'drop N' / 'N less' / 'less N' lower the previous load by N", arguments: [
        "down 10", "drop 10", "10 less", "less 10",
    ])
    func lowerLoad(phrase: String) {
        let previous = workingLoad(100, reps: 5)
        let results = parse(phrase, context: context(previous), library: library)
        #expect(load(of: results)?.load == 90)
    }

    // MARK: - Back-off

    @Test("'back-off' is a working set at 90% of the previous load, rounded to the plate")
    func backOffRoundsToPlate() {
        let previous = workingLoad(110, reps: 6)
        let results = parse("back-off", context: context(previous), library: library)
        // 110 × 0.9 = 99 → nearest 2.5 kg → 100.
        #expect(load(of: results)?.load == 100)
        #expect(load(of: results)?.reps == 6)
    }

     @Test("'back off', 'backoff', and 'back off set' all mean the same back-off", arguments: [
         "back off", "backoff", "back off set",
     ])
    func backOffSpellingVariants(phrase: String) {
        let previous = workingLoad(110, reps: 6)
        let results = parse(phrase, context: context(previous), library: library)
         #expect(load(of: results)?.load == 100)
         #expect(load(of: results)?.reps == 6)
     }

     @Test("a numeric delta keeps the previous set's unit")
    func numericDeltaKeepsThePreviousSetUnit() {
        let previous = workingLoad(100, reps: 5, unit: .pounds)
        let results = parse("up 10", context: context(previous, unit: .pounds), library: library)
         #expect(load(of: results)?.load == 110)
         #expect(load(of: results)?.unit == .pounds)
     }

    // MARK: - Fail closed when there is no previous set

    @Test("a relative phrasing with no previous set logs nothing", arguments: [
        "again", "one more", "up 10", "down 10", "back-off", "add a plate", "drop a plate",
    ])
    func failsClosedWithoutPreviousSet(phrase: String) {
        let results = parse(phrase, context: context(nil), library: library)
        #expect(results.filter { if case .set = $0 { true } else { false } }.isEmpty)
    }

    // MARK: - A load delta needs a load on the previous set

    @Test("a plate step on a loadless previous set is not a load form")
    func plateStepNeedsALoad() {
        let previous = ParsedSet(
            loadType: .bodyweight, effort: .reps, role: .working, grouping: .straight, reps: 10
        )
        let results = parse("add a plate", context: context(previous), library: library)
        #expect(results.filter { if case .set = $0 { true } else { false } }.isEmpty)
    }

    // MARK: - Priority ordering

    @Test("a fully-explicit set still wins over the relative forms")
    func explicitSetBeatsRelative() {
        let previous = workingLoad(100, reps: 5)
        let results = parse("bench 105 for 6", context: context(previous), library: library)
        #expect(results == [
            .announcement(bench, confidence: 1.0),
            .set(ParsedSet(
                loadType: .external, effort: .reps, role: .working, grouping: .straight,
                load: 105, loadUnit: .kilograms, reps: 6
            ), confidence: 1.0),
        ])
    }

    @Test("a relative phrasing that would exceed the plausible ceiling is flagged, not logged")
    func implausibleDeltaIsFlagged() {
        let previous = workingLoad(990, reps: 5)
        let results = parse("up 20", context: context(previous), library: library)
        #expect(results == [.lowConfidence(reason: .implausibleValue, bestGuesses: [bench])])
    }
}
