import Foundation
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
// 6.2: the corpus now lives on disk as one JSON file per row under
// `Fixtures/corpus/` and is loaded via `loadCorpus`. A real corpus (dozens-to-
// hundreds of rows, each tied to a recording) drops into the same directory
// later with zero harness change.
//
// Tracked-metric mode per the spec: assert the ≥ 85% floor only, and surface the
// rows that missed so a grammar regression is visible. Promotion to a hard gate
// waits for the real recogniser feed.

@Suite("Corpus score")
struct CorpusScoreTests {

    @Test("the parse pipeline clears the launch-gate no-correction floor on the corpus")
    func corpusClearsLaunchGateFloor() throws {
        let corpus = try loadCorpus(from: corpusFixturesDirectory())
        let result = score(corpus, library: corpusLibrary)

        #expect(
            result.rate >= 0.85,
            "no-correction rate \(result.rate) over \(result.total) rows; missed: \(result.failures)"
        )
     }

    /// `Fixtures/corpus/`, resolved relative to this source file. The fixtures are
     /// a source-tree artifact, so real recogniser transcripts drop in here later
     /// with no harness change.
    private func corpusFixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
             .deletingLastPathComponent()
             .appendingPathComponent("Fixtures/corpus")
      }
}

// MARK: - Fixtures

// The exercise library every corpus row resolves against.
private let pullUp = Exercise(name: "Pull-Up", aliases: ["pull-ups", "pullups", "pull ups"])
private let plank = Exercise(name: "Plank", aliases: ["plank"])
private let carry = Exercise(name: "Farmer's Carry", aliases: ["farmer carry", "farmers carry"])
private let bench = Exercise(name: "Bench Press", aliases: ["bench", "bench press"])
private let rdl = Exercise(name: "Romanian Deadlift", aliases: ["rdl"])

private let corpusLibrary = ExerciseLibrary([pullUp, plank, carry, bench, rdl])
