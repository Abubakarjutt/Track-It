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
    // `WCSession.activate()` completes asynchronously, but the very first
    // `send(lastWorkoutEndedAt:)` call happens synchronously right after
    // init (WorkoutHistoryModel's init calls reload() immediately). Without
    // caching, that first value is silently dropped by the activation-state
    // guard below and never redelivered until the next real history
    // change — undercutting the "opportunistic delivery" this transport
    // promises. Caching the latest value here and redelivering it once
    // `session(_:activationDidCompleteWith:error:)` fires closes that gap.
    private var pendingLastWorkoutEndedAt: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(lastWorkoutEndedAt: Date?) {
        pendingLastWorkoutEndedAt = lastWorkoutEndedAt
        deliverPending()
    }

    private func deliverPending() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let summary = WatchSummary(lastWorkoutEndedAt: pendingLastWorkoutEndedAt)
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? WCSession.default.updateApplicationContext(["summary": data])
    }

    // WCSession calls its delegate off the main thread. Swift 6's implicit
    // MainActor-by-default inference would otherwise isolate these
    // synchronous ObjC-protocol callbacks to the main actor without the
    // compiler being able to enforce it — ObjC-runtime dispatch calls the
    // method directly on whatever thread WCSession is using, bypassing the
    // actor hop entirely, so an isolated method here would silently run
    // off-actor rather than fail to compile. `nonisolated` keeps that
    // honest. `WCSession.default.activate()` is documented thread-safe.
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            self?.deliverPending()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A new watch may be paired next — re-activate for it (Apple's
        // documented pattern for this callback).
        WCSession.default.activate()
    }
}
