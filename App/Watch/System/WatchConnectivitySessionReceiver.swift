import Foundation
import WatchConnectivity
import WidgetKit

/// Activates `WCSession` on the watch and, whenever the phone pushes a
/// fresh `WatchSummary` via `updateApplicationContext`, writes it into the
/// shared App Group suite and asks WidgetKit to reload the complication.
/// `NSObject` conformance is required by `WCSessionDelegate`. A singleton
/// (`shared`) retained for the watch app's lifetime by `TrackitWatchApp` —
/// mirrors the phone-side `System*` adapters' retained-singleton pattern
/// (cluster 7b/7c).
final class WatchConnectivitySessionReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivitySessionReceiver()

    private override init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["summary"] as? Data,
              let summary = try? JSONDecoder().decode(WatchSummary.self, from: data)
        else { return }
        WatchSummaryStorage.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
