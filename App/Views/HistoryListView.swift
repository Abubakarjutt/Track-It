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
