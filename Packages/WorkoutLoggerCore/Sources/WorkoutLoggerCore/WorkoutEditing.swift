// Post-workout editing — pure Workout → Workout transforms for fixing or
// annotating a completed workout (spec stories 48, 58). Persistence is the
// caller's: apply a transform, then hand the result back to the store.

import Foundation

extension Workout {
    /// A copy with the set at `entryIndex` / `setIndex` replaced by `set`. An
    /// out-of-range index is a no-op.
    public func replacingSet(at entryIndex: Int, _ setIndex: Int, with set: LoggedSet) -> Workout {
        editingSet(at: entryIndex, setIndex) { $0 = set }
    }

    /// A copy with `note` attached to the set at `entryIndex` / `setIndex` — pass
    /// `nil` to clear it. An out-of-range index is a no-op.
    public func annotatingSet(at entryIndex: Int, _ setIndex: Int, with note: String?) -> Workout {
        editingSet(at: entryIndex, setIndex) { $0.note = note }
    }

    /// A copy with the set at `entryIndex` / `setIndex` removed. If that was the
    /// entry's last set the entry goes too — an exercise with no sets is not a
    /// real part of the record (same rule as `undo` on a just-announced entry).
    /// An out-of-range index is a no-op.
    public func removingSet(at entryIndex: Int, _ setIndex: Int) -> Workout {
        guard hasSet(at: entryIndex, setIndex) else { return self }
        var copy = self
        copy.entries[entryIndex].sets.remove(at: setIndex)
        if copy.entries[entryIndex].sets.isEmpty {
            copy.entries.remove(at: entryIndex)
        }
        return copy
    }

    /// A copy carrying `note` as the session note — pass `nil` to clear it.
    public func annotated(with note: String?) -> Workout {
        var copy = self
        copy.note = note
        return copy
    }

    /// Whether `(entryIndex, setIndex)` addresses a real set in this workout.
    private func hasSet(at entryIndex: Int, _ setIndex: Int) -> Bool {
        entries.indices.contains(entryIndex)
            && entries[entryIndex].sets.indices.contains(setIndex)
    }

    /// A copy with `change` applied to the addressed set, or an unchanged copy
    /// when the index is out of range.
    private func editingSet(
        at entryIndex: Int,
        _ setIndex: Int,
        _ change: (inout LoggedSet) -> Void
    ) -> Workout {
        guard hasSet(at: entryIndex, setIndex) else { return self }
        var copy = self
        change(&copy.entries[entryIndex].sets[setIndex])
        return copy
    }
}

/// Turns a completed workout into a reusable template (spec story 58): one item
/// per entry, in order, each planned for the number of working sets it held.
/// Loads and rest targets are dropped — a template holds neither.
public func workoutTemplate(from workout: Workout, named name: String) -> WorkoutTemplate {
    WorkoutTemplate(
        name: name,
        items: workout.entries.map { entry in
            TemplateItem(
                exercise: entry.exercise,
                plannedSets: entry.sets.filter { $0.role == .working }.count
            )
        }
    )
}
