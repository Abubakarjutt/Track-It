import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Reverse-chronological list of completed workouts. A dumb renderer over
/// `WorkoutHistoryModel`.
struct HistoryListView: View {
    let historyModel: WorkoutHistoryModel
    let unit: MassUnit
    let store: WorkoutHistoryStore
    let historyUnavailable: Bool

    /// The row a swipe-to-delete is awaiting confirmation for, or `nil`.
    @State private var pendingDelete: Workout?

    var body: some View {
        Group {
            if historyModel.isUnavailable {
                ContentUnavailableView("History unavailable",
                                       systemImage: "externaldrive.badge.xmark",
                                       description: Text("Storage could not be opened."))
            } else if historyModel.rows.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "list.bullet.rectangle")
            } else {
                List(historyModel.rows, id: \.startedAt) { workout in
                    NavigationLink {
                        WorkoutDetailView(
                            historyModel: historyModel, workout: workout,
                            unit: unit, store: store, historyUnavailable: historyUnavailable
                        )
                        .onAppear { historyModel.open(workout) }
                    } label: {
                        row(for: workout)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = workout
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                // Deleting a whole workout (spec story 35) is unrecoverable —
                // the detail-screen undo stack only spans set edits — so it
                // asks first.
                .confirmationDialog(
                    "Delete this workout?",
                    isPresented: Binding(
                        get: { pendingDelete != nil },
                        set: { if !$0 { pendingDelete = nil } }
                    ),
                    presenting: pendingDelete
                ) { workout in
                    Button("Delete", role: .destructive) {
                        historyModel.deleteWorkout(workout)
                        pendingDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                } message: { _ in
                    Text("This removes the whole workout and every set in it. It can't be undone.")
                }
            }
        }
        .navigationTitle("History")
    }

    /// Date, exercises, working-set volume, and duration (spec stories 2–5). No
    /// prior history is passed in — a list row never shows a personal-record
    /// badge, only the totals — so this is `WorkoutSummaryProjection` at its
    /// cheapest: an empty `priorHistory` short-circuits the badge fold.
    private func row(for workout: Workout) -> some View {
        let summary = WorkoutSummaryProjection(workout: workout, priorHistory: [], unit: unit)
        return VStack(alignment: .leading, spacing: 4) {
            Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text(workout.entries.map(\.exercise.name).joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text("\(summary.totalVolumeText) · \(summary.durationText)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
