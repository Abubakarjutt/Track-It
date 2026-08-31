// The package-testable slice of the spec's "Audio corpus run"
// (specs/v1-voice-logging.md, "Slower / metric tests").
//
// A corpus row is a list of recogniser n-best hypotheses paired with the
// ParseResult sequence a correct log would produce. `score` runs every row
// through the real postProcess → parse chain and reports how many landed with no
// correction, against the launch-gate floor (≥ 85% no-correction).
//
// The on-device recogniser and press-to-confirm latency are out of scope here —
// they need an app shell and a device. The n-best noise in a corpus is authored
// by hand from how the recogniser mangles gym speech, so the score measures the
// post-processor + parser, not the recogniser.

import Foundation

/// One corpus row: the recogniser's n-best hypotheses (best-first) and the
/// ParseResult sequence a no-correction log should yield.
public struct CorpusEntry: Sendable {
    public let hypotheses: [String]
    public let expected: [ParseResult]
    /// Human-readable label for the row, surfaced when it misses.
    public let note: String

    public init(hypotheses: [String], expected: [ParseResult], note: String) {
        self.hypotheses = hypotheses
        self.expected = expected
        self.note = note
    }
}

/// The outcome of running a corpus through the parse pipeline.
public struct CorpusScore: Sendable {
    public let total: Int
    public let matched: Int
    /// `note` of every row whose parse result did not match `expected`.
    public let failures: [String]

    /// Fraction of rows that logged with no correction. An empty corpus scores 1.
    public var rate: Double {
        total == 0 ? 1 : Double(matched) / Double(total)
    }
}

/// Runs every corpus row through the real `postProcess` then `parse` and scores
/// the exact-match rate. `library` is the exercise library all rows resolve
/// against; context is the default (kilograms, no active exercise).
public func score(_ entries: [CorpusEntry], library: ExerciseLibrary) -> CorpusScore {
    var matched = 0
    var failures: [String] = []
    for entry in entries {
        let transcript = postProcess(entry.hypotheses, library: library)
        let results = parse(transcript, context: WorkoutContext(), library: library)
        if results == entry.expected {
            matched += 1
        } else {
            failures.append(entry.note)
        }
    }
    return CorpusScore(total: entries.count, matched: matched, failures: failures)
}
