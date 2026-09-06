import Foundation

/// Where a `TelemetryEvent` goes. The real `System` implementation (in `App/`)
/// is a local, batched-when-online persistent queue; here it is an injected seam
/// so the recorder's flag behaviour can be tested with a capturing fake. A
/// no-op default keeps telemetry from doing anything when it is not wired.
public protocol TelemetrySink: AnyObject {
    func record(_ event: TelemetryEvent)
    /// Drop any not-yet-delivered events. Called when the user turns analytics
    /// off — nothing already queued should still be sent. Default: no-op, for
    /// sinks that hold no queue.
    func discardPending()
}

public extension TelemetrySink {
    func discardPending() {}
}

/// The default sink: records nothing. Used when telemetry is not wired, so the
/// logging loop never has a dependency on an analytics backend.
final class NoopTelemetrySink: TelemetrySink {
    public init() {}
    public func record(_ event: TelemetryEvent) {}
}
