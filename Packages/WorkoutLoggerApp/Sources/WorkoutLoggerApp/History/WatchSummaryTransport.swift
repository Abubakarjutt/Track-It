import Foundation

/// Sends the watch's one glanceable fact — the most recently completed
/// workout's `endedAt`, or `nil` — to a paired Apple Watch (cluster 7f,
/// spec OPEN QUESTION 1/4). Primitive-typed so this package needn't depend
/// on any watch-only wire type: `SystemWatchSummaryTransport` (App-layer)
/// builds the real `WatchConnectivity` payload — a `WatchSummary` struct
/// that lives in `App/Watch/Shared` because it must compile for watchOS,
/// which this package does not target — from the `Date?` this hands it.
@MainActor
public protocol WatchSummaryTransport: AnyObject {
    func send(lastWorkoutEndedAt: Date?)
}

/// Default when no paired watch matters (every existing call site, tests
/// unrelated to this seam).
public final class NoOpWatchSummaryTransport: WatchSummaryTransport {
    public init() {}
    public func send(lastWorkoutEndedAt: Date?) {}
}
