import Testing
import WorkoutLoggerCore

// The package-level slice of the spec's "Audio corpus run" (specs/v1-voice-logging.md,
// "Slower / metric tests"): drive canned recogniser n-best hypotheses through the
// REAL postProcess → parse chain and score how many land on the expected result
// with no correction. The on-device recogniser and press-to-confirm latency stay
// out until there is an app shell; the n-best noise here is authored by hand from
// how Apple's recogniser actually mangles gym speech (dropped "for", homophones,
// spoken-number runs), never read back from the parser.
//
// Tracked-metric mode per the spec: assert the ≥ 85% floor only, and surface the
// rows that missed so a grammar regression is visible. Promotion to a hard gate
// waits for the real recogniser feed.

@Suite("Corpus score")
struct CorpusScoreTests {

    @Test("the parse pipeline clears the launch-gate no-correction floor on the corpus")
    func corpusClearsLaunchGateFloor() {
        let result = score(launchGateCorpus, library: corpusLibrary)

        #expect(
            result.rate >= 0.85,
            "no-correction rate \(result.rate) over \(result.total) rows; missed: \(result.failures)"
        )
    }
}

// MARK: - Fixtures

private let pullUp = Exercise(name: "Pull-Up", aliases: ["pull-ups", "pullups", "pull ups"])
private let plank = Exercise(name: "Plank", aliases: ["plank"])
private let carry = Exercise(name: "Farmer's Carry", aliases: ["farmer carry", "farmers carry"])
private let bench = Exercise(name: "Bench Press", aliases: ["bench", "bench press"])
private let rdl = Exercise(name: "Romanian Deadlift", aliases: ["rdl"])

private let corpusLibrary = ExerciseLibrary([pullUp, plank, carry, bench, rdl])

private func externalSet(
    _ load: Double, _ reps: Int, role: SetRole = .working, grouping: Grouping = .straight
) -> ParsedSet {
    ParsedSet(
        loadType: .external, effort: .reps, role: role, grouping: grouping,
        load: load, loadUnit: .kilograms, reps: reps
    )
}

// One row per axis combination the grammar covers, plus each command, plus two
// rows that exercise the post-processor's recovery (best-hypothesis pick, name
// biasing). Expected values follow the spec's axis semantics.
private let launchGateCorpus: [CorpusEntry] = [
    CorpusEntry(
        hypotheses: ["two twenty five for five"],
        expected: [.set(externalSet(225, 5))],
        note: "external / working / straight, spoken compound load"
    ),
    CorpusEntry(
        hypotheses: ["warmup one thirty five for ten"],
        expected: [.set(externalSet(135, 10, role: .warmup))],
        note: "warmup role keyword"
    ),
    CorpusEntry(
        hypotheses: ["dropset forty for twelve"],
        expected: [.set(externalSet(40, 12, grouping: .dropset))],
        note: "dropset grouping keyword"
    ),
    CorpusEntry(
        hypotheses: ["plus twenty five for eight"],
        expected: [.set(ParsedSet(
            loadType: .added, effort: .reps, role: .working, grouping: .straight,
            load: 25, loadUnit: .kilograms, reps: 8
        ))],
        note: "added load keyword"
    ),
    CorpusEntry(
        hypotheses: ["assisted eight minus forty"],
        expected: [.set(ParsedSet(
            loadType: .assisted, effort: .reps, role: .working, grouping: .straight,
            load: 40, loadUnit: .kilograms, reps: 8
        ))],
        note: "assisted load keyword"
    ),
    CorpusEntry(
        hypotheses: ["pull ups twelve"],
        expected: [.announcement(pullUp), .set(ParsedSet(
            loadType: .bodyweight, effort: .reps, role: .working, grouping: .straight,
            reps: 12
        ))],
        note: "bodyweight reps, inline name"
    ),
    CorpusEntry(
        hypotheses: ["plank for sixty seconds"],
        expected: [.announcement(plank), .set(ParsedSet(
            loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
            durationSeconds: 60
        ))],
        note: "duration effort"
    ),
    CorpusEntry(
        hypotheses: ["farmer carry forty meters"],
        expected: [.announcement(carry), .set(ParsedSet(
            loadType: .bodyweight, effort: .distance, role: .working, grouping: .straight,
            distanceMeters: 40
        ))],
        note: "distance effort"
    ),
    CorpusEntry(
        hypotheses: ["bench one eighty five for eight"],
        expected: [.announcement(bench), .set(externalSet(185, 8))],
        note: "inline name + set"
    ),
    CorpusEntry(
        hypotheses: ["start workout"],
        expected: [.command(.startWorkout)],
        note: "command: start workout"
    ),
    CorpusEntry(
        hypotheses: ["undo"],
        expected: [.command(.undo)],
        note: "command: undo"
    ),
    CorpusEntry(
        hypotheses: ["superset"],
        expected: [.command(.startSuperset)],
        note: "command: superset marker"
    ),
    CorpusEntry(
        hypotheses: [
            "bench breast two twenty five for five",
            "bench press two twenty five for five",
        ],
        expected: [.announcement(bench), .set(externalSet(225, 5))],
        note: "post-processor picks the better-resolving hypothesis"
    ),
    CorpusEntry(
        hypotheses: ["romanian deadlif three fifteen for three"],
        expected: [.announcement(rdl), .set(externalSet(315, 3))],
        note: "post-processor biases a misheard name span"
    ),
]
