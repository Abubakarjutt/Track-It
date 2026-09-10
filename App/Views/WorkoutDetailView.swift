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

    @State private var noteText: String = ""

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
                        // Axis corrections the full set editor leaves out (ADR-0001:
                        // effort measure and load type are independent axes) plus
                        // "put this set into a superset run" — story 26's second half,
                        // the grouping toggle in SetEditView can only clear a run.
                        .contextMenu {
                            Menu("Effort measure") {
                                Button("Reps") { historyModel.applyEdit { $0.changingSet(at: entryIndex, setIndex, effort: .reps) } }
                                Button("Duration") { historyModel.applyEdit { $0.changingSet(at: entryIndex, setIndex, effort: .duration) } }
                                Button("Distance") { historyModel.applyEdit { $0.changingSet(at: entryIndex, setIndex, effort: .distance) } }
                            }
                            Menu("Load type") {
                                Button("External") { historyModel.applyEdit { $0.changingSet(at: entryIndex, setIndex, loadType: .external) } }
                                Button("Bodyweight") { historyModel.applyEdit { $0.changingSet(at: entryIndex, setIndex, loadType: .bodyweight) } }
                                Button("Added") { historyModel.applyEdit { $0.changingSet(at: entryIndex, setIndex, loadType: .added) } }
                                Button("Assisted") { historyModel.applyEdit { $0.changingSet(at: entryIndex, setIndex, loadType: .assisted) } }
                            }
                            Menu("Superset run") {
                                ForEach(current.supersetRunIDs, id: \.self) { runID in
                                    Button("Run \(runID)") {
                                        historyModel.applyEdit {
                                            $0.joiningSet(at: entryIndex, setIndex, intoRun: runID)
                                        }
                                    }
                                }
                                Button("New run") {
                                    historyModel.applyEdit {
                                        $0.joiningSet(at: entryIndex, setIndex, intoRun: $0.nextSupersetRunID)
                                    }
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
            }
            Section("Note") {
                TextField("Add a note for this workout", text: $noteText, axis: .vertical)
                if noteText != (current.note ?? "") {
                    Button("Save note") {
                        historyModel.applyEdit { $0.annotated(with: noteText.isEmpty ? nil : noteText) }
                    }
                }
            }
        }
        .navigationTitle(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
        .onAppear { noteText = current.note ?? "" }
        .toolbar {
            // Per-workout edit history — the stacks live on the model and are
            // cleared when a different workout is opened, so these only ever
            // step through edits made to *this* record.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { historyModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!historyModel.canUndo)
                Button { historyModel.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!historyModel.canRedo)
            }
        }
    }
}
