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

    /// A copy with the set at `entryIndex` / `setIndex` moved to `toExercise`. It is
    /// appended to the end of that exercise's existing entry, or to a new entry if
    /// the workout has none. If the move empties the source entry, the entry goes
    /// too (same rule as `removingSet`). Every field of the set is carried verbatim,
    /// including `grouping` and `supersetRunID` — un-grouping a moved set is a
    /// separate `replacingSet` edit. An out-of-range index, or a `toExercise` that
    /// equals the source entry's exercise, is a no-op.
    public func movingSet(at entryIndex: Int, _ setIndex: Int, toExercise: Exercise) -> Workout {
        guard hasSet(at: entryIndex, setIndex) else { return self }
        guard entries[entryIndex].exercise != toExercise else { return self }

        var copy = self
        let moved = copy.entries[entryIndex].sets.remove(at: setIndex)
        if copy.entries[entryIndex].sets.isEmpty {
            copy.entries.remove(at: entryIndex)
        }

        if let target = copy.entries.firstIndex(where: { $0.exercise == toExercise }) {
            copy.entries[target].sets.append(moved)
        } else {
            copy.entries.append(Entry(exercise: toExercise, sets: [moved]))
        }
        return copy
    }

    /// A copy carrying `note` as the session note — pass `nil` to clear it.
    public func annotated(with note: String?) -> Workout {
        var copy = self
        copy.note = note
        return copy
    }

    /// A copy with the set at `entryIndex` / `setIndex` assigned into superset run
    /// `runID` — its `supersetRunID` is set and its `grouping` becomes `.superset`
    /// (a `.superset` grouping without an id would lose the run membership, per
    /// `LoggedSet.supersetRunID`). Completes story 26: the grouping control can
    /// clear a run marker; this puts a set *into* a chosen run. An out-of-range
    /// index is a no-op.
    public func joiningSet(at entryIndex: Int, _ setIndex: Int, intoRun runID: Int) -> Workout {
        editingSet(at: entryIndex, setIndex) {
            $0.supersetRunID = runID
            $0.grouping = .superset
        }
    }

    /// The distinct superset run ids present in this workout, ascending — the
    /// choices a run picker offers. Empty when nothing is grouped.
    public var supersetRunIDs: [Int] {
        Set(entries.flatMap { $0.sets.compactMap(\.supersetRunID) }).sorted()
    }

    /// The id to mint for a brand-new run: one past the highest in use, or `1`.
    public var nextSupersetRunID: Int {
        (supersetRunIDs.max() ?? 0) + 1
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
///
/// Loads are dropped — a template never carries them. Rest targets come out
/// `nil` too, but for a different reason: a `TemplateItem` *can* hold one, yet a
/// completed `Workout` never recorded what the originating template's targets
/// were (they lived on `RestTimer`, not on the record), so there is nothing here
/// to copy. Recovering them would need either rest-target persistence on the
/// workout or re-cloning the origin template by `templateName` — tracked as a
/// cluster-1f follow-up, not done here.
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
