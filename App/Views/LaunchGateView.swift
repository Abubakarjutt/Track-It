import SwiftUI
import WorkoutLoggerApp

/// Resume-or-discard prompt for a stale open workout found at launch.
struct LaunchGateView: View {
    let model: WorkoutSessionModel

    var body: some View {
        VStack(spacing: 32) {
            Text("Unfinished workout")
                .font(.title.bold())
                .foregroundStyle(.white)

            if let workout = model.pendingStaleWorkout {
                Text("Started \(workout.startedAt.formatted(date: .abbreviated, time: .shortened)) and never ended.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button("Resume it") { model.resumePendingStaleWorkout() }
                    .buttonStyle(.borderedProminent)
                Button("Discard it") { model.discardPendingStaleWorkout() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(40)
    }
}
