import Foundation
import Observation
import WorkoutLoggerCore

/// The one place an analytics event is decided. It holds the opt-in flag and
/// drops every event when analytics is off, so all callers can emit freely and
/// the flag is checked in exactly one spot. The core logging loop only ever
/// calls `record(_:)`, which is a no-op when off — analytics can never block
/// or slow it.
@MainActor
@Observable
public final class TelemetryRecorder {
    @ObservationIgnored private let sink: TelemetrySink
    @ObservationIgnored private let settings: SettingsStore

    /// Mirrors `settings.analyticsEnabled` so a view re-renders on toggle.
    public private(set) var isEnabled: Bool

    public init(sink: TelemetrySink, settings: SettingsStore) {
        self.sink = sink
        self.settings = settings
        self.isEnabled = settings.analyticsEnabled
    }

    /// Forward an event to the sink, unless analytics is off.
    public func record(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        sink.record(event)
    }

    /// Flip the opt-in flag. Disabling stops delivery immediately; enabling it
    /// turns delivery back on.
    public func setEnabled(_ enabled: Bool) {
        settings.analyticsEnabled = enabled
        isEnabled = enabled
    }

    /// Coarse, content-free bucketing of a completed workout's duration.
    public static func durationBucket(of workout: Workout) -> WorkoutDurationBucket {
        guard let endedAt = workout.endedAt else { return .underThirtyMinutes }
        let minutes = max(0, endedAt.timeIntervalSince(workout.startedAt) / 60)
        if minutes < 30 { return .underThirtyMinutes }
        if minutes <= 50 { return .thirtyToFiftyMinutes }
        return .overFiftyMinutes
    }
}
