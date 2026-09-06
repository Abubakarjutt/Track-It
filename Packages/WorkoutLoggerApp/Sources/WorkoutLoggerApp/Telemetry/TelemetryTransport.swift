import Foundation

/// Sends one already-encoded telemetry batch. The only network-touching seam
/// in the pipeline; the app supplies a `URLSession` implementation, tests a
/// spy. Throwing means "not delivered" — the uploader keeps the batch and
/// retries later.
public protocol TelemetryTransport: Sendable {
    func send(_ body: Data) async throws
}
