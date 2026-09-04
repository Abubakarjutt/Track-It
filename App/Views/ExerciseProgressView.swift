import SwiftUI
import Charts
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Load, volume, and estimated-1RM trend for one exercise, plus a "vs last time"
/// row. Charts render fixed series over all available history.
struct ExerciseProgressView: View {
    let exercise: Exercise
    let unit: MassUnit
    let store: WorkoutHistoryStore
    let historyUnavailable: Bool

    private var projection: ExerciseProgressProjection {
        ExerciseProgressModel(exercise: exercise, store: store, unit: unit,
                              historyUnavailable: historyUnavailable).projection
    }

    var body: some View {
        let p = projection
        return Group {
            if p.volumeSeries.isEmpty {
                ContentUnavailableView("No history yet",
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("Log \(exercise.name) to see progress."))
            } else {
                List {
                    if let top = p.topSetText { Text("Top set last time: \(top)") }
                    if let c = p.comparison {
                        Section("Vs last time") {
                            if let d = c.topSetLoadDelta { Text("Top set: \(signed(d))") }
                            Text("Volume: \(signed(c.volumeDelta))")
                            if let d = c.estimatedOneRepMaxDelta { Text("Est. 1RM: \(signed(d))") }
                        }
                    }
                    chartSection("Load", p.loadSeries)
                    chartSection("Volume", p.volumeSeries)
                    chartSection("Estimated 1RM", p.estimatedOneRepMaxSeries)
                }
            }
        }
        .navigationTitle(exercise.name)
    }

    private func chartSection(_ title: String, _ points: [ExerciseProgressProjection.Point]) -> some View {
        Section(title) {
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value(title, point.value))
                PointMark(x: .value("Date", point.date), y: .value(title, point.value))
            }
            .frame(height: 160)
        }
    }

    private func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + numberFormatted(value)
    }
    // Local: WorkoutLoggerApp's numberString is module-internal, not visible here.
    private func numberFormatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
