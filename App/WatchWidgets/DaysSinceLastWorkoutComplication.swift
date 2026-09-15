import WidgetKit
import SwiftUI

/// Days since the last completed workout, read from the App Group cache
/// `WatchConnectivitySessionReceiver` (the watch app) writes. Refreshes on
/// a WidgetKit-triggered reload (a fresh phone push while the watch app is
/// reachable) and, independently, at each local midnight so the count
/// advances even with no new push in between — spec OPEN QUESTION 5's
/// "eventually consistent, not real-time" promise.
struct DaysSinceLastWorkoutEntry: TimelineEntry {
    let date: Date
    let lastWorkoutEndedAt: Date?

    var daysSinceLastWorkout: Int? {
        guard let lastWorkoutEndedAt else { return nil }
        return Calendar.current.dateComponents([.day], from: lastWorkoutEndedAt, to: date).day
    }
}

struct DaysSinceLastWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaysSinceLastWorkoutEntry {
        DaysSinceLastWorkoutEntry(date: Date(), lastWorkoutEndedAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DaysSinceLastWorkoutEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaysSinceLastWorkoutEntry>) -> Void) {
        let entry = currentEntry()
        let nextMidnight = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3_600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func currentEntry() -> DaysSinceLastWorkoutEntry {
        DaysSinceLastWorkoutEntry(date: Date(), lastWorkoutEndedAt: WatchSummaryStorage.read()?.lastWorkoutEndedAt)
    }
}

struct DaysSinceLastWorkoutComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaysSinceLastWorkout", provider: DaysSinceLastWorkoutProvider()) { entry in
            DaysSinceLastWorkoutView(entry: entry)
        }
        .configurationDisplayName("Days Since Workout")
        .description("Days since your last logged workout.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

private struct DaysSinceLastWorkoutView: View {
    let entry: DaysSinceLastWorkoutEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        default:
            VStack(spacing: 0) {
                Text(valueText)
                    .font(.title3.monospacedDigit())
                Text("days")
                    .font(.caption2)
            }
        }
    }

    private var valueText: String {
        guard let days = entry.daysSinceLastWorkout else { return "–" }
        return "\(days)"
    }

    private var inlineText: String {
        guard let days = entry.daysSinceLastWorkout else { return "No workouts yet" }
        return days == 0 ? "Workout today" : "\(days)d since workout"
    }
}
