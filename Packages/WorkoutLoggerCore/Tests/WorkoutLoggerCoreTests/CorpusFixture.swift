import Foundation
import WorkoutLoggerCore

// 6.2 disk-fixture harness (test-only).
//
// Core's `ParseResult` is frozen as `Equatable`/`Sendable` and is deliberately
// NOT `Codable` (see the cluster-6 spec's open question 2): a real corpus is
// dozens-to-hundreds of rows, each tied to a recording, so instead of teaching a
// frozen Core type to serialise itself we decode a small JSON *mirror* onto the
// Core types by hand. Real recogniser transcripts drop into
// `Fixtures/corpus/` later with zero harness change.
//
// Fixture shape (one file per row, `note` first so a miss is human-locatable):
//
//   {
//     "note": "external / working / straight, spoken compound load",
//     "hypotheses": ["two twenty five for five"],
//     "expected": [
//       { "kind": "set", "confidence": 1.0,
//         "set": { "loadType": "external", "effort": "reps",
//                  "role": "working", "grouping": "straight",
//                  "load": 225, "loadUnit": "kilograms", "reps": 5 } }
//     ]
//   }
//
// `expected` is a list: one utterance can yield more than one `ParseResult`
// (an announcement followed by its set). Kinds: `set`, `announcement`,
// `command`, `lowConfidence`.

/// One JSON fixture file on disk.
struct CorpusFixture: Decodable {
    let note: String
    let hypotheses: [String]
    let expected: [ResultFixture]
}

/// One expected `ParseResult`, discriminated by `kind`.
struct ResultFixture: Decodable {
    enum Kind: String, Decodable {
        case set, announcement, command, lowConfidence
     }

    let kind: Kind
     /// `set` / `announcement`.
    let confidence: Double?
     /// `command`.
    let command: String?
     /// `lowConfidence`.
    let reason: String?
     /// `announcement`.
    let exercise: ExerciseFixture?
     /// `set`.
    let set: SetFixture?
     /// `lowConfidence` (may be empty / absent).
    let bestGuesses: [ExerciseFixture]?

    func parseResult() throws -> ParseResult {
        switch kind {
        case .set:
             let confidence = try require(confidence, "confidence")
             let set = try require(set, "set")
             return .set(try set.makeSet(), confidence: confidence)
        case .announcement:
             let confidence = try require(confidence, "confidence")
             let exercise = try require(exercise, "exercise")
             return .announcement(exercise.makeExercise(), confidence: confidence)
        case .command:
             let name = try require(command, "command")
             return .command(try CommandFixture.map(name))
        case .lowConfidence:
             let reason = try LowConfidenceFixture.map(try require(reason, "reason"))
             let guesses = bestGuesses?.map { $0.makeExercise() } ?? []
             return .lowConfidence(reason: reason, bestGuesses: guesses)
        }
     }
}

/// `Exercise` is `Codable`, but we mirror it so a fixture's `aliases` may be
/// omitted (the parser resolves names/aliases, the fixture just names the
/// exercise) and the shape stays obvious.
struct ExerciseFixture: Decodable {
    let name: String
    let aliases: [String]?

    func makeExercise() -> Exercise { Exercise(name: name, aliases: aliases ?? []) }
}

/// The four always-present axes plus the optional numeric slot.
struct SetFixture: Decodable {
    let loadType: String
    let effort: String
    let role: String
    let grouping: String
    let load: Double?
    let loadUnit: String?
    let reps: Int?
    let durationSeconds: Int?
    let distanceMeters: Double?

    func makeSet() throws -> ParsedSet {
        ParsedSet(
            loadType: try Axis.loadType(loadType),
            effort: try Axis.effort(effort),
            role: try Axis.role(role),
            grouping: try Axis.grouping(grouping),
            load: load,
            loadUnit: try loadUnit.map { try Axis.massUnit($0) },
            reps: reps,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters
         )
     }
}

/// String → Core enum mappings. Explicit (not synthesized) so the JSON format is
/// stable and independent of how Core's `Codable` axis enums serialise.
enum Axis {
    static func loadType(_ s: String) throws -> LoadType {
        switch s {
        case "external": return .external
        case "bodyweight": return .bodyweight
        case "added": return .added
        case "assisted": return .assisted
        default: throw FixtureError.unmapped("loadType", s)
        }
     }

    static func effort(_ s: String) throws -> EffortMeasure {
        switch s {
        case "reps": return .reps
        case "duration": return .duration
        case "distance": return .distance
        default: throw FixtureError.unmapped("effort", s)
        }
     }

    static func role(_ s: String) throws -> SetRole {
        switch s {
        case "working": return .working
        case "warmup": return .warmup
        default: throw FixtureError.unmapped("role", s)
        }
     }

    static func grouping(_ s: String) throws -> Grouping {
        switch s {
        case "straight": return .straight
        case "superset": return .superset
        case "dropset": return .dropset
        default: throw FixtureError.unmapped("grouping", s)
        }
     }

    static func massUnit(_ s: String) throws -> MassUnit {
        switch s {
        case "kilograms": return .kilograms
        case "pounds": return .pounds
        default: throw FixtureError.unmapped("loadUnit", s)
        }
     }
}

enum CommandFixture {
    static func map(_ s: String) throws -> Command {
        switch s {
        case "undo": return .undo
        case "startRest": return .startRest
        case "skipRest": return .skipRest
        case "help": return .help
        case "startWorkout": return .startWorkout
        case "endWorkout": return .endWorkout
        case "startSuperset": return .startSuperset
        case "endSuperset": return .endSuperset
        default: throw FixtureError.unmapped("command", s)
        }
     }
}

enum LowConfidenceFixture {
    static func map(_ s: String) throws -> LowConfidenceReason {
        switch s {
        case "unrecognisedExercise": return .unrecognisedExercise
        case "implausibleValue": return .implausibleValue
        default: throw FixtureError.unmapped("reason", s)
        }
     }
}

private func require<T>(_ value: T?, _ field: String) throws -> T {
    guard let value else { throw FixtureError.missing(field) }
    return value
}

/// Reads every `*.json` under `directory` (sorted by file name for a stable
/// order) into `[CorpusEntry]`. Throws on a missing/empty directory: an empty
/// load would score 1.0 and mask a corpus that failed to load.
func loadCorpus(from directory: URL) throws -> [CorpusEntry] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: directory.path, isDirectory: &isDir),
          isDir.boolValue
    else {
        throw FixtureError.missingDirectory(directory.path)
     }

    let files = try fm
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else {
        throw FixtureError.emptyCorpus(directory.path)
     }

    var entries: [CorpusEntry] = []
    for file in files {
        let data = try Data(contentsOf: file)
        let fixture = try JSONDecoder().decode(CorpusFixture.self, from: data)
        entries.append(
            CorpusEntry(
                hypotheses: fixture.hypotheses,
                expected: try fixture.expected.map { try $0.parseResult() },
                note: fixture.note
             )
         )
     }
    return entries
}

enum FixtureError: Error, CustomStringConvertible {
    case missing(String)
    case unmapped(String, String)
    case missingDirectory(String)
    case emptyCorpus(String)

    var description: String {
        switch self {
        case .missing(let field):
             return "fixture is missing required field '\(field)'"
        case .unmapped(let field, let value):
             return "fixture field '\(field)' has no mapping for '\(value)'"
        case .missingDirectory(let path):
             return "corpus directory not found: \(path)"
        case .emptyCorpus(let path):
             return "corpus directory has no .json fixtures: \(path)"
        }
     }
}
