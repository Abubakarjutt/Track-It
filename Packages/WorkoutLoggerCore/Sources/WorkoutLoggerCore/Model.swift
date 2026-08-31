// Domain types for the voice workout logger. Vocabulary follows CONTEXT.md.

/// A movement in the app's library, e.g. "Barbell Bench Press".
public struct Exercise: Equatable, Sendable, Codable {
    public let name: String
    /// Alternative spoken names that resolve to this exercise, e.g. "OHP".
    public let aliases: [String]

    public init(name: String, aliases: [String] = []) {
        self.name = name
        self.aliases = aliases
    }
}

/// The curated core plus any custom exercises, with their aliases.
public struct ExerciseLibrary: Sendable {
    public let exercises: [Exercise]

    public init(_ exercises: [Exercise]) {
        self.exercises = exercises
    }

    public static let empty = ExerciseLibrary([])
}

/// The unit a load is expressed in.
public enum MassUnit: Equatable, Sendable, Codable {
    case kilograms
    case pounds
}

// The four independent axes of a Set.
// See docs/adr/0001-set-modelled-as-orthogonal-axes.md.

public enum LoadType: Equatable, Sendable, Codable {
    case external
    case bodyweight
    case added
    case assisted
}

public enum EffortMeasure: Equatable, Sendable, Codable {
    case reps
    case duration
    case distance
}

public enum SetRole: Equatable, Sendable, Codable {
    case working
    case warmup
}

public enum Grouping: Equatable, Sendable, Codable {
    case straight
    case superset
    case dropset
}

/// A set as produced by the parser, before the workout engine attaches it to an entry.
public struct ParsedSet: Equatable, Sendable {
    public var loadType: LoadType
    public var effort: EffortMeasure
    public var role: SetRole
    public var grouping: Grouping
    public var load: Double?
    public var loadUnit: MassUnit?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?

    public init(
        loadType: LoadType,
        effort: EffortMeasure,
        role: SetRole,
        grouping: Grouping,
        load: Double? = nil,
        loadUnit: MassUnit? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil
    ) {
        self.loadType = loadType
        self.effort = effort
        self.role = role
        self.grouping = grouping
        self.load = load
        self.loadUnit = loadUnit
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }
}

/// The outcome of matching a spoken name against the library. Seam B.
public enum ExerciseResolution: Equatable, Sendable {
    case resolved(Exercise, confidence: Double)
    case unresolved(bestGuesses: [Exercise])
}

/// What the parser knows about the workout in progress when it interprets an utterance.
///
/// Only `unit` shapes parsing today. `activeExercise` and `previousSet` are part
/// of the seam contract for the workout engine (Phase 2/3): the engine attaches
/// each `ParsedSet` to the active exercise, and repeat-to-retry compares against
/// `previousSet`. They are carried here so the seam does not change shape when
/// that logic lands.
public struct WorkoutContext: Sendable {
    public var activeExercise: Exercise?
    public var previousSet: ParsedSet?
    public var unit: MassUnit

    public init(
        activeExercise: Exercise? = nil,
        previousSet: ParsedSet? = nil,
        unit: MassUnit = .kilograms
    ) {
        self.activeExercise = activeExercise
        self.previousSet = previousSet
        self.unit = unit
    }
}

/// An instruction to the app rather than a set. A small, fixed vocabulary.
public enum Command: Equatable, Sendable {
    case undo
    case startRest
    case skipRest
    case help
    case startWorkout
    case endWorkout
    case startSuperset
    case endSuperset
}

/// Why the parser could not confidently interpret an utterance.
public enum LowConfidenceReason: Equatable, Sendable {
    case unrecognisedExercise
    /// A numeric slot (load or reps) came out too large to be a real set — a
    /// magnitude mis-hear rather than a set anyone performed.
    case implausibleValue
}

/// One interpreted item from a transcript.
public enum ParseResult: Equatable, Sendable {
    case set(ParsedSet)
    case announcement(Exercise)
    case command(Command)
    /// The parser could not confidently place an exercise. `bestGuesses` is the
    /// resolver's ranked shortlist (may be empty) for the tap-select fallback.
    case lowConfidence(reason: LowConfidenceReason, bestGuesses: [Exercise])
}
