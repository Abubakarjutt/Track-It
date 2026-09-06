import Foundation

/// A `TelemetrySink` for tests: records every event handed to it, in order.
/// Drives the recorder's flag-gated behaviour; the system sink (in `App/`) is
/// not compiled here.
public final class CaptureTelemetrySink: TelemetrySink {
    public private(set) var events: [TelemetryEvent] = []
    public init() {}
    public func record(_ event: TelemetryEvent) {
        events.append(event)
    }
}
