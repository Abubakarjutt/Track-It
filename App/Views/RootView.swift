import SwiftUI
import Combine
import WorkoutLoggerApp

/// Top-level container: shows the resume-or-discard prompt while one is pending,
/// otherwise the HUD. Owns the 1 Hz rest tick and the keep-awake bridge.
///
/// Ownership: `TrackitApp` owns the `@Observable` `WorkoutSessionModel` in its
/// `@State`; this view holds it as a plain `let` (SwiftUI still tracks the
/// `@Observable` reads in `body`). `import Combine` is for `Timer.publish`.
struct RootView: View {
    let model: WorkoutSessionModel
    let historyUnavailable: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.pendingStaleWorkout != nil {
                LaunchGateView(model: model)
            } else {
                HUDView(model: model, historyUnavailable: historyUnavailable)
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(tick) { _ in model.tick() }
        .onChange(of: model.keepScreenAwake, initial: true) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
