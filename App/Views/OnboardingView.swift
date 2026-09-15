import SwiftUI
import WorkoutLoggerApp

/// One-screen first-run permission priming. Shares `LaunchGateView`'s centred
/// column and, like it, follows `settingsModel.appearance` rather than the
/// HUD's forced-dark canvas (`RootView`). "Continue" fires the system speech +
/// mic prompts; the caller dismisses this screen afterwards regardless of the
/// outcome (`OnboardingModel.completeOnboarding()` sets the latch either way).
struct OnboardingView: View {
    let model: OnboardingModel

    @State private var working = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Speak your sets")
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)

            Text("Trackit turns each set you say out loud into a workout log, "
                 + "on device. It listens only while you hold the talk button — "
                 + "nothing leaves your phone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Continue") {
                working = true
                Task {
                    await model.completeOnboarding()
                    working = false
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)
        }
        .padding(40)
    }
}
