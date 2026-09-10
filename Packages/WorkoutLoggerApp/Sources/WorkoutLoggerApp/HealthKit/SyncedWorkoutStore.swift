import Foundation
import SwiftData

/// The persistent record of which completed workouts are already in Apple
/// Health, keyed on `Workout.startedAt`. The HealthKit writer consults it
/// before a write (so a relaunch can't double-post) and updates it after a
/// clean write. `SwiftData`-backed in the app; an in-memory set in tests.
@MainActor
public protocol SyncedWorkoutStore: AnyObject {
    /// Whether the workout that started at `startedAt` has been written to Health.
    func isSynced(startedAt: Date) -> Bool
    /// Record that the workout starting at `startedAt` is now in Health. A start
    /// time already recorded is left as-is.
    func markSynced(startedAt: Date)
    /// Drop every record — the "delete all workout data" path, so a later
    /// workout that happens to reuse a start time is not wrongly skipped.
    func forgetAll()
}

/// In-memory `SyncedWorkoutStore` for tests and for the default
/// `HealthKitSyncModel` before a real store is wired.
@MainActor
public final class InMemorySyncedWorkoutStore: SyncedWorkoutStore {
    private var startTimes: Set<Date> = []

    public init() {}

    public func isSynced(startedAt: Date) -> Bool { startTimes.contains(startedAt) }
    public func markSynced(startedAt: Date) { startTimes.insert(startedAt) }
    public func forgetAll() { startTimes.removeAll() }
}

/// SwiftData-backed `SyncedWorkoutStore` over the shared container. `@Attribute(.unique)`
/// on `SyncedWorkoutRecord.startedAt` makes `markSynced` idempotent; a failed
/// fetch or save is swallowed here — a missed dedupe entry costs at most one
/// duplicate `HKWorkout` the user can delete, the same worst case v1 accepted.
@MainActor
public final class SwiftDataSyncedWorkoutStore: SyncedWorkoutStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func isSynced(startedAt: Date) -> Bool {
        let key = startedAt
        let descriptor = FetchDescriptor<SyncedWorkoutRecord>(
            predicate: #Predicate { $0.startedAt == key }
        )
        return ((try? context.fetch(descriptor))?.isEmpty == false)
    }

    public func markSynced(startedAt: Date) {
        guard !isSynced(startedAt: startedAt) else { return }
        context.insert(SyncedWorkoutRecord(startedAt: startedAt))
        try? context.save()
    }

    public func forgetAll() {
        try? context.delete(model: SyncedWorkoutRecord.self)
        try? context.save()
    }
}
