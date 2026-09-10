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

    /// Whether there is a prior state to `undo()` / a undone state to `redo()`.
    /// Both stacks hold whole-`Workout` snapshots for the currently open workout
    /// and are cleared whenever a different workout is opened or one is deleted.
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    private var undoStack: [Workout] = []
    private var redoStack: [Workout] = []

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
        clearEditHistory()
        reload()
    }

    public func open(_ workout: Workout) {
        let isDifferentWorkout = selected?.startedAt != workout.startedAt
        selected = rows.first { $0.startedAt == workout.startedAt }
        // Re-entering the same detail screen (the history list fires `open` on
        // every `.onAppear`) must not throw away edits made this visit — only a
        // genuinely different workout resets the stacks.
        if isDifferentWorkout { clearEditHistory() }
    }

    /// Delete one workout from history, then reload. If it was the workout open
    /// on the detail screen, `selected` is cleared so nothing renders a record
    /// that no longer exists (spec story 35 — delete a whole workout, not just
    /// its sets).
    public func deleteWorkout(_ workout: Workout) {
        store.deleteWorkout(startedAt: workout.startedAt)
        if let error = store.lastSaveError {
            saveError = String(describing: error)
            return
        }
        saveError = nil
        if selected?.startedAt == workout.startedAt {
            selected = nil
            clearEditHistory()
        }
        reload()
    }

    /// Applies `transform` to the open workout, saves it, and reloads the list.
    /// The store never throws — it records a failure in `lastSaveError` — so on a
    /// failure this discards the edited copy, leaves `selected` as it was, and
    /// skips the reload, keeping the on-screen state honest about what persisted.
    public func applyEdit(_ transform: (Workout) -> Workout) {
        guard let current = selected else { return }
        persist(transform(current)) {
            undoStack.append(current)   // the pre-edit state to fall back to
            redoStack.removeAll()       // a new edit forks the timeline
        }
    }

    /// Restore the workout to its state before the last edit, persisting the
    /// revert as its own save. A no-op with nothing to undo; a failed save is
    /// surfaced in `saveError` and leaves the stacks intact.
    public func undo() {
        guard let current = selected, let previous = undoStack.last else { return }
        persist(previous) {
            undoStack.removeLast()
            redoStack.append(current)
        }
    }

    /// Re-apply the most recently undone edit. Mirror of `undo()`.
    public func redo() {
        guard let current = selected, let next = redoStack.last else { return }
        persist(next) {
            redoStack.removeLast()
            undoStack.append(current)
        }
    }

    /// Save `workout`; on success run `mutateStacks`, reload the list, and
    /// re-select the row for `workout`. A store failure is surfaced in
    /// `saveError` and nothing else changes — the shared spine of `applyEdit`,
    /// `undo`, and `redo`, which differ only in how they move the two stacks.
    private func persist(_ workout: Workout, _ mutateStacks: () -> Void) {
        store.save(workout)
        if let error = store.lastSaveError {
            saveError = String(describing: error)
            return
        }
        saveError = nil
        mutateStacks()
        reload()
        selected = rows.first { $0.startedAt == workout.startedAt }
    }

    private func clearEditHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
