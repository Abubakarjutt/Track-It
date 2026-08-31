import SwiftUI
import Combine
import WorkoutLoggerApp

/// Placeholder root. Enough to smoke-test the whole voice loop on a device;
/// the calm high-contrast HUD is subsystem C.
///
/// Ownership (pre-flight Ruling 3): `TrackitApp` owns the `@Observable`
/// `WorkoutSessionModel` in its `@State`. This child is *handed* that model, so
/// it holds it as a plain `let` — SwiftUI still tracks the `@Observable`
/// property reads in `body`. `import Combine` is for `Timer.publish`.
struct RootView: View {
    let model: WorkoutSessionModel

    var body: some View {
        VStack(spacing: 24) {
            Text(model.workout?.entries.last?.exercise.name ?? "No exercise")
                .font(.title2)

            if let set = model.workout?.entries.last?.sets.last {
                Text("\(set.loadKilograms.map { "\($0) kg " } ?? "")\(set.reps.map { "x \($0)" } ?? "")")
                    .font(.largeTitle.bold())
            }

            Text(model.restStartedAt == nil ? "" : "Rest \(Int(model.restElapsed))s")
                .foregroundStyle(.secondary)

            Button(model.isListening ? "Listening…" : "Hold to talk") {}
                .buttonStyle(.borderedProminent)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !model.isListening { model.pressed() } }
                        .onEnded { _ in Task { await model.released() } }
                )

            if let candidates = model.tapSelectCandidates, !candidates.isEmpty {
                ForEach(candidates, id: \.name) { exercise in
                    Button("Did you mean \(exercise.name)?") { model.resolveTapSelect(exercise) }
                }
            }
        }
        .padding()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            model.tick()
        }
    }
}
