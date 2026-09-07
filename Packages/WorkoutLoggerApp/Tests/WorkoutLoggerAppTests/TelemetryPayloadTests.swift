import Testing
import Foundation
@testable import WorkoutLoggerApp

@Suite("Telemetry payload — content-free serialization")
struct TelemetryPayloadTests {

    /// One of every TelemetryEvent case. If a case is added without a codec
    /// arm this stops compiling (the switch in payload(for:) is exhaustive).
    private let everyEvent: [TelemetryEvent] = [
        .workoutStarted,
        .workoutCompleted(totalSetCount: 30, workingSetCount: 24, duration: .thirtyToFiftyMinutes),
        .setLogged,
        .parseFailed,
        .correctionMade,
        .featureUsed(.export),
        .featureUsed(.templateSaved),
        .setLoggedLatency(millisBucket: 400),
    ]

    @Test("every encoded event object uses only allow-listed keys")
    func onlyAllowedKeys() throws {
        let payload = TelemetryPayload(
            installID: "00000000-0000-0000-0000-000000000000",
            events: everyEvent.map(TelemetryPayloadCodec.payload(for:))
        )
        let data = try JSONEncoder().encode(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(root.keys) == ["install_id", "events"])
        let objects = try #require(root["events"] as? [[String: Any]])
        for object in objects {
            let keys = Set(object.keys)
            #expect(keys.isSubset(of: TelemetryPayloadCodec.allowedKeys),
                    "unexpected keys \(keys.subtracting(TelemetryPayloadCodec.allowedKeys))")
        }
    }

    @Test("workoutCompleted carries only counts and a coarse bucket spelling")
    func completedShape() {
        let p = TelemetryPayloadCodec.payload(
            for: .workoutCompleted(totalSetCount: 12, workingSetCount: 9, duration: .overFiftyMinutes)
        )
        #expect(p.kind == "workout_completed")
        #expect(p.totalSets == 12)
        #expect(p.workingSets == 9)
        #expect(p.durationBucket == "over_fifty")
        #expect(p.feature == nil)
        #expect(p.latencyBucketMillis == nil)
    }

    @Test("a feature event carries a fixed feature spelling and nothing else")
    func featureShape() {
        let p = TelemetryPayloadCodec.payload(for: .featureUsed(.healthSyncToggle))
        #expect(p.kind == "feature_used")
        #expect(p.feature == "health_sync_toggle")
        #expect(p.totalSets == nil && p.workingSets == nil && p.durationBucket == nil)
    }

    @Test("a latency event carries only its bucket")
    func latencyShape() {
        let p = TelemetryPayloadCodec.payload(for: .setLoggedLatency(millisBucket: 700))
        #expect(p.kind == "set_logged_latency")
        #expect(p.latencyBucketMillis == 700)
        #expect(p.feature == nil && p.totalSets == nil)
    }

    @Test("a nil field is omitted from JSON, not encoded as null")
    func nilFieldsOmitted() throws {
        let data = try JSONEncoder().encode(TelemetryPayloadCodec.payload(for: .setLogged))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Array(object.keys) == ["kind"])
    }
}
