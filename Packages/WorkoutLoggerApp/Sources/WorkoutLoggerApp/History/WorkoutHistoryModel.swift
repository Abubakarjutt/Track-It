import Foundation
import Observation
import WorkoutLoggerCore

/// Owns the completed-workout list and the edit-then-resave loop for the detail
/// screen. Editing runs a pure `WorkoutLoggerCore` transform on the open workout
/// and saves the result under its unchanged `startedAt`, so an edit overwrites
/// the workout's own record — never a duplicate (spec story 35).
@MainActor
@Observable
public final class WorkoutHistoryModel {
    /// Completed workouts, most recent first.
    public private(set) var rows: [Workout] = []
    /// The workout open on the detail screen, or `nil`.
    public private(set) var selected: Workout?
    /// A human-readable description of the last failed save, or `nil`.
    public private(set) var saveError: String?
    /// Storage could not be opened at launch — the list shows "unavailable",
    /// distinct from an empty history (spec story 10 vs 9).
    public let isUnavailable: Bool

    @ObservationIgnored private let store: WorkoutHistoryStore

    public init(store: WorkoutHistoryStore, historyUnavailable: Bool = false) {
        self.store = store
        self.isUnavailable = historyUnavailable
        reload()
    }

    public func reload() {
        rows = isUnavailable ? [] : Array(store.history().filter(\.isEnded).reversed())
    }

    /// Erase every stored workout, then reload. The exercise library and
    /// preferences are separate stores and survive. `selected` is cleared so
    /// the detail screen can't hold a workout that no longer exists.
    public func deleteAllWorkoutData() {
        store.deleteAllWorkouts()
        selected = nil
        reload()
    }

    public func open(_ workout: Workout) {
        selected = rows.first { $0.startedAt == workout.startedAt }
    }

    /// Applies `transform` to the open workout, saves it, and reloads the list.
    /// The store never throws — it records a failure in `lastSaveError` — so on a
    /// failure this discards the edited copy, leaves `selected` as it was, and
    /// skips the reload, keeping the on-screen state honest about what persisted.
    public func applyEdit(_ transform: (Workout) -> Workout) {
        guard let current = selected else { return }
        let edited = transform(current)
        store.save(edited)
        if let error = store.lastSaveError {
            saveError = String(describing: error)
            return
        }
        saveError = nil
        reload()
        selected = rows.first { $0.startedAt == edited.startedAt }
    }
}
