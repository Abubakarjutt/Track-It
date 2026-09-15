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
        Group {
            if onboardingModel.shouldShowOnboarding {
                OnboardingView(model: onboardingModel)
            } else if model.pendingStaleWorkout != nil {
                LaunchGateView(model: model)
            } else {
                NavigationStack {
                    HUDView(model: model, historyUnavailable: historyUnavailable)
                        // Scoped to the HUD's own content, not the NavigationStack
                        // itself — a pushed destination (History, Progress,
                        // Settings, and everything under them) is a separate view
                        // inserted onto the stack, not a descendant of this one, so
                        // it isn't forced dark by this and instead picks up
                        // `colorScheme` below like the rest of the app.
                        .background(Color.black.ignoresSafeArea())
                        .preferredColorScheme(.dark)
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
                                    MuscleGroupStimulusView(
                                        store: store,
                                        historyUnavailable: historyUnavailable
                                    )
                                } label: {
                                    Image(systemName: "chart.bar.fill")
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
        .preferredColorScheme(nonHUDColorScheme)
        .onReceive(tick) { _ in model.tick() }
        .onChange(of: model.keepScreenAwake, initial: true) { _, _ in syncIdleTimer() }
        .onChange(of: scenePhase) { _, _ in syncIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// The non-HUD colour scheme, derived from the setting: `nil` follows the
    /// system. The HUD branch overrides this locally with its own unconditional
    /// `.preferredColorScheme(.dark)` — see `body`. Named `nonHUD...` rather
    /// than the shorter `colorScheme` to avoid colliding with SwiftUI's own
    /// `ColorScheme` type and `@Environment(\.colorScheme)` vocabulary.
    private var nonHUDColorScheme: ColorScheme? {
        switch settingsModel.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Keep the screen awake only while a workout is open *and* the app is
    /// foreground-active. iOS ignores `isIdleTimerDisabled` off the active
    /// phase anyway, but the spec asks us to reset it explicitly on the way out.
    private func syncIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = (scenePhase == .active && model.keepScreenAwake)
    }
}
