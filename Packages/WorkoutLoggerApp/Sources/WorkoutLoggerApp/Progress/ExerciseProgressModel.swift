import Foundation
import Observation
import WorkoutLoggerCore

/// Backs the per-exercise progress screen. Reads completed history once at
/// construction, folds it with the core `exerciseProgress` function, and holds
/// the drawable projection. Rebuilt (not mutated) when the screen is reopened.
@MainActor
@Observable
public final class ExerciseProgressModel {
    public private(set) var projection: ExerciseProgressProjection

    public init(exercise: Exercise, store: WorkoutHistoryStore, unit: MassUnit,
                historyUnavailable: Bool = false) {
        let history = historyUnavailable ? [] : store.history().filter(\.isEnded)
        let progress = exerciseProgress(for: exercise, across: history)
        projection = ExerciseProgressProjection(progress: progress, unit: unit)
    }
}
