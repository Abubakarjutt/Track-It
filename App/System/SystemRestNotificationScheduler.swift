import Foundation
import UserNotifications
import WorkoutLoggerApp

/// `RestNotificationScheduler` over `UNUserNotificationCenter` (cluster 7c).
/// One fixed identifier ("rest-complete") — `add(_:)` with a repeated
/// identifier replaces the pending request, so `schedule(deadline:)` never
/// needs to explicitly cancel before scheduling a new one.
@MainActor
final class SystemRestNotificationScheduler: RestNotificationScheduler {
    private static let identifier = "rest-complete"
    private let center = UNUserNotificationCenter.current()

    func schedule(deadline: Date) {
        // Fire-and-forget, like SystemSpeechRecognizer's
        // SFSpeechRecognizer.requestAuthorization — the real gate is the
        // system permission prompt itself; a denial just means this
        // specific notification never shows, which is the same silent
        // no-op UNUserNotificationCenter gives a denied `add` outright.
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Back to it — your next set is up."
        content.sound = .default

        // A deadline already in the past (e.g. reconciling a very late
        // foreground open) still fires promptly rather than being silently
        // dropped — UNTimeIntervalNotificationTrigger requires a positive
        // interval.
        let interval = max(0.1, deadline.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier, content: content, trigger: trigger
        )
        center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}
