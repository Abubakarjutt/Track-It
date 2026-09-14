import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// This week's per-muscle-group training stimulus: the working-set count for each
/// muscle group across the current Monday-start calendar week, attributed flat per
/// group, plus an "unclassified" row for exercises the map doesn't know. A dumb
/// renderer over `MuscleGroupStimulusModel` — rebuilt (like the other progress
/// views) each time the screen appears, not mutated.
struct MuscleGroupStimulusView: View {
    let store: WorkoutHistoryStore
    let historyUnavailable: Bool

     private var model: MuscleGroupStimulusModel {
        MuscleGroupStimulusModel(store: store, historyUnavailable: historyUnavailable)
      }

    var body: some View {
        let week = model.currentWeek
        let peak = maxCount(week)
        return Group {
            if week.total == 0 {
                ContentUnavailableView("No stimulus this week",
                                       systemImage: "chart.bar.fill",
                                       description: Text("Log a workout to see per-muscle-group stimulus."))
              } else {
                List {
                    ForEach(MuscleGroup.allCases, id: \.self) { group in
                        // Only the groups trained this week, in the stable
                        // allCases order.
                        if let count = week.perGroup[group], count > 0 {
                            row(label: group.displayName, count: count, max: peak)
                         }
                     }
                    if week.unclassified > 0 {
                        Section("Unclassified") {
                            row(label: "Unknown exercises", count: week.unclassified, max: peak)
                         }
                     }
                 }
             }
          }
         .navigationTitle("Muscle group")
      }

     /// The busiest single-group count this week, so each bar is relative to it
     /// (floored at 1 so a lone set still fills its own bar).
    private func maxCount(_ week: MuscleGroupSetVolume) -> Int {
        max(1, (week.perGroup.values.max() ?? 0), week.unclassified)
      }

     private func row(label: String, count: Int, max: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(count), total: Double(max))
         }
      }
}
