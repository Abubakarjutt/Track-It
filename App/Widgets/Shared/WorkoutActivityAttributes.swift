import Foundation
import ActivityKit

/// The Live Activity's content contract (cluster 7c) — primitives only, no
/// `WorkoutLoggerCore`/`WorkoutLoggerApp` dependency, since this file
/// compiles into BOTH the app target and the `TrackitWidgets` extension
/// target. `App/System/LiveActivityController` maps
/// `WorkoutLoggerApp.WorkoutActivityState` into `ContentState` 1:1.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var workingSetCount: Int
        var isResting: Bool
        var restDeadline: Date?
        var isListening: Bool
    }
}
