import Foundation

/// Turns a press-to-logged span into the content-free forms telemetry uses:
/// a 100 ms bucket per set, and a batch median for the tracked launch-gate
/// metric (spec § "Success gates": ≤ 3 s median).
public enum LatencyMetric {

    /// `seconds` rounded to the nearest 100 ms. Negative input (a clock that
    /// went backwards) clamps to 0 rather than reporting a nonsense bucket.
    public static func bucketMillis(_ seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        return Int((seconds * 1000 / 100).rounded()) * 100
    }

    /// Median of the buckets carried by the `.setLoggedLatency` events in
    /// `events`, or `nil` when there are none. Even counts take the
    /// lower-middle element — a stable, dependency-free definition for a
    /// tracked metric.
    ///
    /// Not called at runtime yet: this is the exact definition of the
    /// spec's launch gate (≤ 3 s median press-to-confirmed-set), kept here
    /// for the device-loop analysis (#7) and any future server-side
    /// aggregation to share one definition rather than reinvent it.
    public static func medianBucketMillis(of events: [TelemetryEvent]) -> Int? {
        let buckets = events
            .compactMap { event -> Int? in
                if case let .setLoggedLatency(millis) = event { return millis }
                return nil
            }
            .sorted()
        guard !buckets.isEmpty else { return nil }
        return buckets[(buckets.count - 1) / 2]
    }
}
