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

/// A `TelemetryTransport` for tests: records every batch body, and throws
/// `failWith` instead when it is set (to drive the uploader's retry path).
public final class SpyTelemetryTransport: TelemetryTransport, @unchecked Sendable {
    public private(set) var sentBodies: [Data] = []
    public private(set) var sendCount = 0
    public var failWith: Error?

    public init() {}

    public func send(_ body: Data) async throws {
        sendCount += 1
        if let failWith { throw failWith }
        sentBodies.append(body)
    }
}
