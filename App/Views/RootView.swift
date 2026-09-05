import SwiftUI
import UIKit
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
    let historyModel: WorkoutHistoryModel
    let store: any WorkoutHistoryStore
    let historyUnavailable: Bool
    let settingsModel: SettingsModel
    let onboardingModel: OnboardingModel

    @Environment(\.scenePhase) private var scenePhase
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if onboardingModel.shouldShowOnboarding {
                OnboardingView(model: onboardingModel)
            } else if model.pendingStaleWorkout != nil {
                LaunchGateView(model: model)
            } else {
                NavigationStack {
                    HUDView(model: model, historyUnavailable: historyUnavailable)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    HistoryListView(
                                        historyModel: historyModel,
                                        unit: model.displayUnit,
                                        store: store,
                                        historyUnavailable: historyUnavailable
                                    )
                                } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView(model: settingsModel)
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(tick) { _ in model.tick() }
        .onChange(of: model.keepScreenAwake, initial: true) { _, _ in syncIdleTimer() }
        .onChange(of: scenePhase) { _, _ in syncIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// Keep the screen awake only while a workout is open *and* the app is
    /// foreground-active. iOS ignores `isIdleTimerDisabled` off the active
    /// phase anyway, but the spec asks us to reset it explicitly on the way out.
    private func syncIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = (scenePhase == .active && model.keepScreenAwake)
    }
}
