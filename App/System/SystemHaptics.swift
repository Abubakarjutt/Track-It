import Foundation
import UIKit
import WorkoutLoggerApp

/// Real haptics: a `UINotificationFeedbackGenerator` mapping for the four cues.
/// (A bespoke CoreHaptics pattern set is a later polish; the notification
/// generator gives four distinguishable feels now.) `@MainActor` because
/// `Haptics` is `@MainActor`-isolated (Task 7) — and `UIFeedbackGenerator` is
/// main-actor API anyway.
@MainActor
final class SystemHaptics: Haptics {
    private let notify = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .rigid)

    func play(_ cue: HapticCue) {
        switch cue {
        case .logged:         impact.impactOccurred()
        case .notCaught:      notify.notificationOccurred(.error)
        case .personalRecord: notify.notificationOccurred(.success)
        case .restReached:    notify.notificationOccurred(.warning)
        case .none:           break
        }
    }
}
