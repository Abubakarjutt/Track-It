import Foundation

/// The exact JSON body posted to the analytics endpoint: a content-free
/// install id plus a batch of event objects. `installID` is a random UUID
/// with no tie to the device, the user, or any workout.
public struct TelemetryPayload: Codable, Equatable, Sendable {
    public let installID: String
    public let events: [TelemetryEventPayload]

    public init(installID: String, events: [TelemetryEventPayload]) {
        self.installID = installID
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case events
    }
}

/// One event on the wire. Every field is a coarse fact — a kind string, a
/// count, a fixed bucket/feature spelling. There is no field that can hold a
/// load, an exercise name, or a transcript. `nil` fields are omitted.
public struct TelemetryEventPayload: Codable, Equatable, Sendable {
    public var kind: String
    public var totalSets: Int?
    public var workingSets: Int?
    public var durationBucket: String?
    public var feature: String?
    public var latencyBucketMillis: Int?

    public init(
        kind: String,
        totalSets: Int? = nil,
        workingSets: Int? = nil,
        durationBucket: String? = nil,
        feature: String? = nil,
        latencyBucketMillis: Int? = nil
    ) {
        self.kind = kind
        self.totalSets = totalSets
        self.workingSets = workingSets
        self.durationBucket = durationBucket
        self.feature = feature
        self.latencyBucketMillis = latencyBucketMillis
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case totalSets = "total_sets"
        case workingSets = "working_sets"
        case durationBucket = "duration_bucket"
        case feature
        case latencyBucketMillis = "latency_bucket_millis"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(totalSets, forKey: .totalSets)
        try c.encodeIfPresent(workingSets, forKey: .workingSets)
        try c.encodeIfPresent(durationBucket, forKey: .durationBucket)
        try c.encodeIfPresent(feature, forKey: .feature)
        try c.encodeIfPresent(latencyBucketMillis, forKey: .latencyBucketMillis)
    }
}

/// The one place a `TelemetryEvent` becomes wire bytes. The switch is
/// exhaustive, so a new event case cannot ship without a reviewer deciding
/// its content-free shape here.
public enum TelemetryPayloadCodec {

    /// Every JSON key any event object may contain. Asserted in
    /// `TelemetryPayloadTests`.
    public static let allowedKeys: Set<String> = [
        "kind", "total_sets", "working_sets",
        "duration_bucket", "feature", "latency_bucket_millis",
    ]

    public static func payload(for event: TelemetryEvent) -> TelemetryEventPayload {
        switch event {
        case .workoutStarted:
            return TelemetryEventPayload(kind: "workout_started")
        case let .workoutCompleted(total, working, duration):
            return TelemetryEventPayload(
                kind: "workout_completed",
                totalSets: total,
                workingSets: working,
                durationBucket: spelling(for: duration)
            )
        case .setLogged:
            return TelemetryEventPayload(kind: "set_logged")
        case .parseFailed:
            return TelemetryEventPayload(kind: "parse_failed")
        case .correctionMade:
            return TelemetryEventPayload(kind: "correction_made")
        case let .featureUsed(feature):
            return TelemetryEventPayload(kind: "feature_used", feature: spelling(for: feature))
        case let .setLoggedLatency(bucket):
            return TelemetryEventPayload(kind: "set_logged_latency", latencyBucketMillis: bucket)
        }
    }

    private static func spelling(for bucket: WorkoutDurationBucket) -> String {
        switch bucket {
        case .underThirtyMinutes: return "under_thirty"
        case .thirtyToFiftyMinutes: return "thirty_to_fifty"
        case .overFiftyMinutes: return "over_fifty"
        }
    }

    private static func spelling(for feature: TelemetryFeature) -> String {
        switch feature {
        case .export: return "export"
        case .healthSyncToggle: return "health_sync_toggle"
        case .analyticsToggle: return "analytics_toggle"
        case .recognitionReviewToggle: return "recognition_review_toggle"
        case .settingsOpened: return "settings_opened"
        case .templateSaved: return "template_saved"
        }
    }
}
