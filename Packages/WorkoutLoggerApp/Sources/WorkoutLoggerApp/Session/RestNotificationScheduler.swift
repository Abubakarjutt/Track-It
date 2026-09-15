import Foundation

/// Schedules the "rest is over" signal for when the app can't rely on a live
/// `tick()` loop to notice — backgrounded or the screen locked (cluster 7c).
/// One outstanding schedule at a time: `schedule(deadline:)` implicitly
/// replaces whatever was pending; `cancel()` clears it without replacement.
@MainActor
public protocol RestNotificationScheduler: AnyObject {
    func schedule(deadline: Date)
    func cancel()
}

/// The default when no real scheduler is supplied — tests and any composition
/// root that doesn't care about the backgrounded case get inert no-ops rather
/// than a crash or an optional to unwrap everywhere.
public final class NoOpRestNotificationScheduler: RestNotificationScheduler {
    public init() {}
    public func schedule(deadline: Date) {}
    public func cancel() {}
}
