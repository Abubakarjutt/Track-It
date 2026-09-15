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
///
/// `@MainActor` here isn't about the delegate callbacks (see below) — it's
/// what makes `static let shared` satisfy Swift 6's concurrency-safety
/// check for a non-`Sendable` class's shared mutable state (this project's
/// established fix for that shape; see the phone-side
/// `SystemWatchSummaryTransport`'s equivalent isolation note).
@MainActor
final class WatchConnectivitySessionReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivitySessionReceiver()

    private override init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // WCSession calls its delegate off the main thread; ObjC-runtime
    // dispatch bypasses any actor hop Swift could otherwise enforce, so
    // these stay nonisolated rather than implicitly inheriting the type's
    // @MainActor above (same reasoning as SystemWatchSummaryTransport).
    // UserDefaults writes and WidgetCenter.reloadAllTimelines() are both
    // documented safe to call from any thread.
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["summary"] as? Data,
              let summary = try? JSONDecoder().decode(WatchSummary.self, from: data)
        else { return }
        WatchSummaryStorage.write(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
