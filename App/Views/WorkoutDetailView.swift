import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// One completed workout: entries, formatted set lines with PR badges, totals,
/// and the note. Row tap opens the set editor; exercise-name tap opens progress.
struct WorkoutDetailView: View {
    let historyModel: WorkoutHistoryModel
    let workout: Workout
    let unit: MassUnit
    let store: WorkoutHistoryStore
    let historyUnavailable: Bool

    private var summary: WorkoutSummaryProjection {
        let prior = historyModel.rows.filter { $0.startedAt < workout.startedAt }
        return WorkoutSummaryProjection(workout: workout, priorHistory: prior, unit: unit)
    }

    /// The live workout value edits run against (falls back to the passed-in one
    /// before the first `open`).
    private var current: Workout { historyModel.selected ?? workout }

    var body: some View {
        List {
            if let error = historyModel.saveError {
                Text("Couldn’t save: \(error)").foregroundStyle(.red)
            }
            ForEach(Array(summary.entries.enumerated()), id: \.offset) { entryIndex, entry in
                Section {
                    ForEach(Array(entry.sets.enumerated()), id: \.offset) { setIndex, row in
                        NavigationLink {
                            SetEditView(
                                set: current.entries[entryIndex].sets[setIndex],
                                exerciseNames: current.entries.map(\.exercise.name),
                                unit: unit
                            ) { edited in
                                // One atomic transform → one save.
                                historyModel.applyEdit { w in
                                    var next = w.replacingSet(at: entryIndex, setIndex, with: edited.set)
                                    if let target = edited.moveToExerciseName, target != entry.exerciseName {
                                        next = next.movingSet(at: entryIndex, setIndex,
                                                              toExercise: Exercise(name: target))
                                    }
                                    return next
                                }
                            } onDelete: {
                                historyModel.applyEdit { $0.removingSet(at: entryIndex, setIndex) }
                            }
                        } label: {
                            HStack {
                                Text(row.line).font(.body.monospacedDigit())
                                if row.isPersonalRecord {
                                    Spacer(); Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                }
                            }
                        }
                    }
                } header: {
                    NavigationLink(entry.exerciseName) {
                        ExerciseProgressView(
                            exercise: current.entries[entryIndex].exercise,   // real value, aliases intact
                            unit: unit, store: store, historyUnavailable: historyUnavailable
                        )
                    }
                }
            }
            Section("Totals") {
                Text("Volume: \(summary.totalVolumeText)")
                Text("Working reps: \(summary.totalWorkingReps)")
                Text("Duration: \(summary.durationText)")
                if let note = summary.note { Text(note).italic() }
            }
        }
        .navigationTitle(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
    }
}
