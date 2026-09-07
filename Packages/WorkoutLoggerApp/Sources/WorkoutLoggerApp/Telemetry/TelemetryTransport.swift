import Foundation

/// Sends one already-encoded telemetry batch. The only network-touching seam
/// in the pipeline; the app supplies a `URLSession` implementation, tests a
/// spy. Throwing means "not delivered" — by default the uploader keeps the
/// batch and retries later. Throw `TelemetryTransportError.permanent` to say
/// the endpoint rejected this batch in a way retrying cannot fix, so the
/// uploader should drop it and move on.
public protocol TelemetryTransport: Sendable {
    func send(_ body: Data) async throws
}

/// A delivery failure the uploader treats specially. Any *other* thrown
/// error — a raw `URLError`, a test's stub error — is transient: keep the
/// batch, back off, retry.
///
/// The status-code split is provisional (see issue #6): it is a best-guess
/// 4xx taxonomy pending the real ingest endpoint's contract.
public enum TelemetryTransportError: Error, Equatable, Sendable {
    /// The endpoint rejected the batch and will keep rejecting it — a 4xx the
    /// server owns (malformed body, unknown route, payload too large). The
    /// uploader drops the batch rather than wedging the queue behind it.
    case permanent(statusCode: Int)
}
