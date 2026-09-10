import Foundation
import SwiftData

/// One completed workout that has been written to Apple Health, keyed on its
/// `startedAt`. Its own tiny `@Model` in the same container as `WorkoutRecord`
/// and `ExerciseRecord` (mirroring `SettingsStore`'s bucket style) so the
/// HealthKit writer can tell — across a relaunch, not just within a session —
/// which workouts are already in Health and must not be posted twice.
/// "Delete all workout data" clears these alongside the `WorkoutRecord`s.
@Model
public final class SyncedWorkoutRecord {
    @Attribute(.unique) public var startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}
