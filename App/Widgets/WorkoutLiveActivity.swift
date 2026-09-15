import ActivityKit
import WidgetKit
import SwiftUI

/// The lock-screen + Dynamic Island presentation of the workout Live
/// Activity (cluster 7c). Read-only (OPEN QUESTION 7 resolution) — no
/// buttons, no App Intent target. Layout follows OPEN QUESTION 4's
/// resolution: minimal = a dot; compact = a mic glyph (idle/listening) or
/// the rest countdown (resting), mutually exclusive; expanded = exercise
/// name + set count + rest countdown.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ExpandedView(state: context.state)
                }
            } compactLeading: {
                CompactView(state: context.state)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Circle().fill(.tint).frame(width: 6, height: 6)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.exerciseName).font(.headline)
            Text("\(state.workingSetCount) working set\(state.workingSetCount == 1 ? "" : "s")")
                .font(.subheadline)
            if state.isResting, let deadline = state.restDeadline {
                Text(timerInterval: Date()...deadline, countsDown: true)
                    .font(.title3.monospacedDigit())
            }
        }
        .padding()
    }
}

private struct ExpandedView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.exerciseName).font(.headline)
            Text("\(state.workingSetCount) working set\(state.workingSetCount == 1 ? "" : "s")")
                .font(.caption)
            if state.isResting, let deadline = state.restDeadline {
                Text(timerInterval: Date()...deadline, countsDown: true)
                    .font(.body.monospacedDigit())
            }
        }
    }
}

private struct CompactView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isResting, let deadline = state.restDeadline {
            Text(timerInterval: Date()...deadline, countsDown: true)
                .font(.caption.monospacedDigit())
        } else {
            Image(systemName: state.isListening ? "mic.fill" : "mic")
        }
    }
}
