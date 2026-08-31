import Foundation
import SwiftData
import WorkoutLoggerCore

/// SwiftData-backed `WorkoutStore`. The engine calls `save` on every set with the
/// whole growing `Workout`; this upserts one `WorkoutRecord` per session keyed on
/// `startedAt`. Reads decode the JSON payload back into `Workout` values for the
/// pure `WorkoutLoggerCore` functions (progress, stale-check) to consume.
public final class SwiftDataWorkoutStore: WorkoutStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(context: ModelContext) {
        self.context = context
    }

    public func save(_ workout: Workout) {
        guard let payload = try? encoder.encode(workout) else { return }
        let key = workout.startedAt
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startedAt == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.endedAt = workout.endedAt
        } else {
            context.insert(WorkoutRecord(
                startedAt: workout.startedAt, endedAt: workout.endedAt, payload: payload
            ))
        }
        try? context.save()
    }

    public func history() -> [Workout] {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap { try? decoder.decode(Workout.self, from: $0.payload) }
    }

    public func openWorkout() -> Workout? {
        history().last { !$0.isEnded }
    }
}
