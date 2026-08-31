import Foundation
import SwiftData
import WorkoutLoggerCore

/// SwiftData-backed `WorkoutStore`. The engine calls `save` on every set with the
/// whole growing `Workout`; this upserts one `WorkoutRecord` per session keyed on
/// `startedAt`. Reads decode the JSON payload back into `Workout` values for the
/// pure `WorkoutLoggerCore` functions (progress, stale-check) to consume.
///
/// The payload is a versioned envelope (`StoredWorkout`) so a future
/// non-optional field on `WorkoutLoggerCore.Workout` fails loudly (counted in
/// `decodeFailureCount`) instead of every stored workout silently vanishing. A
/// bare legacy `Workout` payload still decodes. `save` cannot throw (the
/// `WorkoutStore` protocol forbids it), so a failed encode/fetch/`context.save`
/// is surfaced through `lastSaveError` rather than swallowed.
public final class SwiftDataWorkoutStore: WorkoutStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The error from the most recent `save(_:)`, or `nil` if it succeeded.
    public private(set) var lastSaveError: Error?
    /// How many stored payloads have failed to decode as either a versioned
    /// envelope of a known version or a legacy bare `Workout`.
    public private(set) var decodeFailureCount = 0

    /// The persisted payload: a format version plus the workout it wraps.
    private struct StoredWorkout: Codable {
        var v: Int
        var workout: Workout
    }
    private static let currentFormatVersion = 1

    public init(context: ModelContext) {
        self.context = context
    }

    public func save(_ workout: Workout) {
        lastSaveError = nil
        do {
            let payload = try encoder.encode(
                StoredWorkout(v: Self.currentFormatVersion, workout: workout)
            )
            let key = workout.startedAt
            let descriptor = FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate { $0.startedAt == key }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.payload = payload
                existing.endedAt = workout.endedAt
            } else {
                context.insert(WorkoutRecord(
                    startedAt: workout.startedAt, endedAt: workout.endedAt, payload: payload
                ))
            }
            try context.save()
        } catch {
            lastSaveError = error
        }
    }

    public func history() -> [Workout] {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap { decode($0.payload) }
    }

    public func openWorkout() -> Workout? {
        history().last { !$0.isEnded }
    }

    /// Decodes one stored payload. Tries the versioned envelope first, then the
    /// legacy bare form; a payload that is neither (or an envelope of an
    /// unrecognised version) is counted in `decodeFailureCount`, never dropped
    /// on the floor.
    private func decode(_ payload: Data) -> Workout? {
        if let stored = try? decoder.decode(StoredWorkout.self, from: payload),
           stored.v == Self.currentFormatVersion {
            return stored.workout
        }
        if let bare = try? decoder.decode(Workout.self, from: payload) {
            return bare
        }
        decodeFailureCount += 1
        return nil
    }
}
