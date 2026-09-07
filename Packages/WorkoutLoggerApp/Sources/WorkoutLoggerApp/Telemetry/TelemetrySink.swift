import Foundation

/// Where a `TelemetryEvent` goes. The app wires this to `TelemetryUploader`
/// (persisted queue + batched `URLSession` delivery + back-off, backed by
/// `FileTelemetryQueueStore`); tests inject a capturing fake so the recorder's
/// flag behaviour is checkable in isolation. A no-op `discardPending` default
/// keeps sinks that hold no queue trivially conformant.
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
