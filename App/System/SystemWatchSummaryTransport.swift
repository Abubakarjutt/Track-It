import Foundation
import WatchConnectivity
import WorkoutLoggerApp

/// Real `WatchConnectivity`-backed `WatchSummaryTransport` (cluster 7f).
/// `updateApplicationContext` is "latest value wins, delivered
/// opportunistically" — exactly the read-only, eventually-consistent
/// promise spec OPEN QUESTION 5 confirms. `NSObject` conformance is
/// required by `WCSessionDelegate`; the delegate methods below are
/// required by the protocol on this platform even though this type sends
/// and never receives.
final class SystemWatchSummaryTransport: NSObject, WatchSummaryTransport, WCSessionDelegate {
    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(lastWorkoutEndedAt: Date?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let summary = WatchSummary(lastWorkoutEndedAt: lastWorkoutEndedAt)
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? WCSession.default.updateApplicationContext(["summary": data])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A new watch may be paired next — re-activate for it (Apple's
        // documented pattern for this callback).
        WCSession.default.activate()
    }
}
