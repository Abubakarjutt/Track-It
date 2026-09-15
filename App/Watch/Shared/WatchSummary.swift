import Foundation

/// The one glanceable fact cluster 7f's watch complication shows, encoded
/// over `WatchConnectivity` and cached in an App-Group `UserDefaults` suite
/// on the watch side. Deliberately primitives-only with no
/// `WorkoutLoggerCore`/`WorkoutLoggerApp` dependency: this file compiles
/// into the iOS `Trackit` target, the watchOS `TrackitWatch` app, and the
/// watchOS `TrackitWatchWidgets` extension (see `project.yml`), and neither
/// Swift package targets watchOS.
public struct WatchSummary: Codable, Equatable, Sendable {
    /// The most recently completed workout's `endedAt`, or `nil` with no
    /// completed workouts yet.
    public let lastWorkoutEndedAt: Date?

    public init(lastWorkoutEndedAt: Date?) {
        self.lastWorkoutEndedAt = lastWorkoutEndedAt
    }
}

/// Where the watch-side `WatchConnectivity` receiver writes the latest
/// summary, and where the widget extension's `TimelineProvider` reads it
/// from — the two watch-side processes don't share memory, only this App
/// Group suite.
public enum WatchSummaryStorage {
    public static let appGroupSuiteName = "group.com.abubakarsahi.trackit.watch"
    public static let userDefaultsKey = "watchSummary"

    public static func read() -> WatchSummary? {
        guard let data = UserDefaults(suiteName: appGroupSuiteName)?.data(forKey: userDefaultsKey)
        else { return nil }
        return try? JSONDecoder().decode(WatchSummary.self, from: data)
    }

    public static func write(_ summary: WatchSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        UserDefaults(suiteName: appGroupSuiteName)?.set(data, forKey: userDefaultsKey)
    }
}
