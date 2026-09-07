import Foundation
import WorkoutLoggerApp

/// `TelemetryTransport` over `URLSession`. POSTs the JSON batch to the
/// first-party analytics endpoint; a non-2xx or a network error throws, so
/// the uploader keeps the batch and retries. No response body is read.
struct TelemetryHTTPTransport: TelemetryTransport {
    /// First-party ingest endpoint. Placeholder host — confirm before the
    /// public build; the shape (POST, `application/json`, the `TelemetryPayload`
    /// body) is fixed by spec § "Telemetry transport".
    static let defaultEndpoint = URL(string: "https://telemetry.trackit.abubakarsahi.com/v1/events")!

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
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
