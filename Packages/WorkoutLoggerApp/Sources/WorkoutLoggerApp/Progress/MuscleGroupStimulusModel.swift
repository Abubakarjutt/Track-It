import Foundation
import Observation
import WorkoutLoggerCore

/// Backs the per-muscle-group progress screen. Reads completed history once at
/// construction, folds it with `MuscleMap.setVolume(_:in:)` over the *current*
/// Monday-start calendar week, and holds the drawable result. Rebuilt (not
/// mutated) when the screen is reopened — the same shape as `ExerciseProgressModel`.
@MainActor
@Observable
public final class MuscleGroupStimulusModel {
     /// The per-group stimulus for the current week, plus the `unclassified`
     /// bucket. All zeros when history is unavailable or no working sets fall in
     /// the week.
    public private(set) var currentWeek: MuscleGroupSetVolume

     /// No stimulus this week — the view shows a `ContentUnavailableView`.
    public var isEmpty: Bool { currentWeek.total == 0 }

     /// Build from `store`'s completed history over the week containing `now`.
     /// `map` / `now` / `calendar` default to the shipped map and the current
     /// moment so the app's call site is a one-liner; tests inject all three for
     /// a deterministic window. `historyUnavailable` (storage could not be opened)
     /// yields an empty week rather than a crash (spec story 10 vs 9).
    public init(store: WorkoutHistoryStore,
                map: MuscleMap = defaultMuscleMap,
                now: Date = Date(),
                calendar: Calendar = .current,
                historyUnavailable: Bool = false) {
        let history = historyUnavailable ? [] : store.history().filter(\.isEnded)
        currentWeek = map.setVolume(across: history, in: calendarWeek(containing: now, in: calendar))
     }
}
