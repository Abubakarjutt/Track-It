import Testing
import Foundation
@testable import WorkoutLoggerApp

@Suite("Latency metric")
struct LatencyMetricTests {

    @Test("a span rounds to the nearest 100 ms")
    func rounding() {
        #expect(LatencyMetric.bucketMillis(0) == 0)
        #expect(LatencyMetric.bucketMillis(0.04) == 0)
        #expect(LatencyMetric.bucketMillis(0.05) == 100)
        #expect(LatencyMetric.bucketMillis(0.44) == 400)
        #expect(LatencyMetric.bucketMillis(2.98) == 3000)
    }

    @Test("a negative span clamps to zero")
    func negativeClamps() {
        #expect(LatencyMetric.bucketMillis(-1.5) == 0)
    }

    @Test("median pulls only setLoggedLatency events, odd count")
    func medianOdd() {
        let events: [TelemetryEvent] = [
            .setLogged,
            .setLoggedLatency(millisBucket: 300),
            .workoutStarted,
            .setLoggedLatency(millisBucket: 100),
            .setLoggedLatency(millisBucket: 500),
        ]
        #expect(LatencyMetric.medianBucketMillis(of: events) == 300)
    }

    @Test("median of an even count takes the lower-middle element")
    func medianEven() {
        let events: [TelemetryEvent] = [
            .setLoggedLatency(millisBucket: 400),
            .setLoggedLatency(millisBucket: 100),
            .setLoggedLatency(millisBucket: 300),
            .setLoggedLatency(millisBucket: 200),
        ]
        #expect(LatencyMetric.medianBucketMillis(of: events) == 200)
    }

    @Test("no latency events yields nil")
    func noneYieldsNil() {
        #expect(LatencyMetric.medianBucketMillis(of: [.setLogged, .workoutStarted]) == nil)
    }
}
