import Foundation
import WorkoutLoggerApp

/// `TelemetryTransport` over `URLSession`. POSTs the JSON batch to the
/// first-party analytics endpoint. A 2xx is delivery. A 4xx the server owns
/// (malformed body, unknown route, payload too large) throws
/// `TelemetryTransportError.permanent`, so the uploader drops the batch
/// rather than retrying it forever. Everything else — 408/429, any 5xx, a
/// network error — throws plain, which the uploader treats as transient and
/// retries with back-off. No response body is read.
struct TelemetryHTTPTransport: TelemetryTransport {
    /// First-party ingest endpoint. TODO(#6): placeholder host — set to the
    /// real ingest host before shipping analytics enabled; the status-code
    /// taxonomy below is provisional until that endpoint's contract is fixed.
    /// The shape (POST, `application/json`, the `TelemetryPayload` body) is
    /// fixed by spec § "Telemetry transport".
    static let defaultEndpoint = URL(string: "https://telemetry.trackit.abubakarsahi.com/v1/events")!

    /// 4xx codes that will not change on retry — drop the batch.
    private static let permanentStatusCodes: Set<Int> = [400, 404, 413, 422]

    let endpoint: URL
    let session: URLSession

    init(endpoint: URL = Self.defaultEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func send(_ body: Data) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)   // no HTTP response — transient
        }
        if (200..<300).contains(http.statusCode) {
            return
        }
        if Self.permanentStatusCodes.contains(http.statusCode) {
            throw TelemetryTransportError.permanent(statusCode: http.statusCode)
        }
        throw URLError(.badServerResponse)       // 408/429/5xx/other — transient, retry with back-off
    }
}
