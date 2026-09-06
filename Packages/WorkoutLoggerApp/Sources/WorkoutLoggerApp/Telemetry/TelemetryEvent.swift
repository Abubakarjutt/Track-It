import Foundation

/// A coarse bucket of a completed workout's duration. Telemetry reports only the
/// bucket, never the exact elapsed time — a small integer ordinal, not a `Double`
/// in seconds there to leak a precise measurement.
public enum WorkoutDurationBucket: Equatable, Sendable {
    case underThirtyMinutes
    case thirtyToFiftyMinutes
    case overFiftyMinutes
}

/// The opt-in features a `.featureUsed` event can name. A closed list — the only
/// strings that can ever ride a telemetry event are these fixed spellings, and
/// none of them is a load, an exercise name, a transcript, or any free-form
/// text. This enum is the structural guarantee behind the "no content" promise.
public enum TelemetryFeature: Equatable, Sendable {
    case export
    case healthSyncToggle
    case analyticsToggle
    case recognitionReviewToggle
    case settingsOpened
    case templateSaved
}

/// An anonymous analytics event. Every case carries only coarse, content-free
/// facts — a kind, a count, a bucket, or one of the fixed `TelemetryFeature`
/// cases. There is no case with a load, an exercise name, a transcript, or any
/// free-form `String`, so no code path can put workout content into an event.
public enum TelemetryEvent: Equatable, Sendable {
    case workoutStarted
    case workoutCompleted(totalSetCount: Int, workingSetCount: Int, duration: WorkoutDurationBucket)
    case setLogged
    case parseFailed
    case correctionMade
    case featureUsed(TelemetryFeature)
}
