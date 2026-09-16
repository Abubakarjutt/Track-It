import Foundation
import WorkoutLoggerApp

/// `TelemetryTransport` over `URLSession`, backed by PostHog's `/batch/`
/// ingest API. The package's own wire format (`TelemetryPayload`'s
/// vendor-neutral `{"install_id","events"}`, spec § "Telemetry transport")
/// stays fixed; this adapter alone knows PostHog's request shape
/// (`{"api_key","batch":[{"event","distinct_id","properties"}]}`) and
/// reshapes into it in `send(_:)`, so a future vendor swap touches only
/// this file. A 2xx is delivery. A 4xx the server owns (malformed body,
/// unknown route, payload too large) throws `TelemetryTransportError
/// .permanent`, so the uploader drops the batch rather than retrying it
/// forever. Everything else — 408/429, any 5xx, a network error — throws
/// plain, which the uploader treats as transient and retries with
/// back-off. No response body is read.
struct TelemetryHTTPTransport: TelemetryTransport {
    /// PostHog US Cloud batch-ingest endpoint. TODO(#6): status-code
    /// taxonomy below is provisional until reconciled against PostHog's
    /// actual `/batch/` error contract.
    static let defaultEndpoint = URL(string: "https://us.i.posthog.com/batch/")!

    /// TODO(#6): placeholder PostHog Project API key — replace with the
    /// real project's key before shipping analytics enabled. A PostHog
    /// *project* API key (as opposed to a *personal* API key) is a
    /// write-only ingestion credential PostHog's own docs say is safe to
    /// embed in client code.
    static let placeholderAPIKey = "phc_REPLACE_BEFORE_SHIP"

    /// 4xx codes that will not change on retry — drop the batch.
    /// Deliberately excludes 401/403: an auth failure is a client-config
    /// problem the operator can fix, so it stays transient and keeps retrying
    /// rather than silently discarding events. 413 is safe here only because
    /// the uploader never shrinks a batch — if it ever splits oversized
    /// batches, 413 must move out of this set.
    private static let permanentStatusCodes: Set<Int> = [400, 404, 413, 422]

    let endpoint: URL
    let apiKey: String
    let session: URLSession

    init(
        endpoint: URL = Self.defaultEndpoint,
        apiKey: String = Self.placeholderAPIKey,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    func send(_ body: Data) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.posthogBatch(from: body, apiKey: apiKey)
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

    /// Reshapes the package's vendor-neutral payload into PostHog's
    /// `/batch/` request body. Every `TelemetryEventPayload` field becomes
    /// a PostHog event property except `kind`, which becomes the event
    /// name; `installID` becomes `distinct_id` on every event in the
    /// batch (it is the one identity PostHog needs — content-free, per
    /// `TelemetryPayload`'s own doc comment).
    static func posthogBatch(from body: Data, apiKey: String) throws -> Data {
        let payload = try JSONDecoder().decode(TelemetryPayload.self, from: body)
        let batch: [[String: Any]] = payload.events.map { event in
            var properties: [String: Any] = [:]
            if let totalSets = event.totalSets { properties["total_sets"] = totalSets }
            if let workingSets = event.workingSets { properties["working_sets"] = workingSets }
            if let durationBucket = event.durationBucket { properties["duration_bucket"] = durationBucket }
            if let feature = event.feature { properties["feature"] = feature }
            if let latencyBucketMillis = event.latencyBucketMillis {
                properties["latency_bucket_millis"] = latencyBucketMillis
            }
            return [
                "event": event.kind,
                "distinct_id": payload.installID,
                "properties": properties,
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "api_key": apiKey,
            "batch": batch,
        ])
    }
}
