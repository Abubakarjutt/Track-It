import Foundation
import SwiftData

/// One completed workout that has been written to Apple Health, keyed on its
/// `startedAt`. Its own tiny `@Model` in the same container as `WorkoutRecord`
/// and `ExerciseRecord` (mirroring `SettingsStore`'s bucket style) so the
/// HealthKit writer can tell — across a relaunch, not just within a session —
/// which workouts are already in Health and must not be posted twice.
/// "Delete all workout data" clears these alongside the `WorkoutRecord`s.
/// No `@Attribute(.unique)` (cluster 7a, CloudKit mirroring doesn't support
/// it) -- `SwiftDataSyncedWorkoutStore.markSynced`'s own `isSynced` guard
/// already enforces uniqueness at the app layer. The default below is never
/// actually read (every real instance goes through `init`) -- CloudKit
/// mirroring requires every attribute be optional or carry one.
@Model
public final class SyncedWorkoutRecord {
    public var startedAt: Date = Date.distantPast

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}
