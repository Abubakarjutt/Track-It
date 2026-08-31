import Foundation
import SwiftData

/// One persisted workout: the engine's per-session `startedAt` as the natural
/// key, `endedAt` mirrored out for cheap "is a workout still open" checks, and
/// the whole `WorkoutLoggerCore.Workout` value JSON-encoded in `payload`.
@Model
public final class WorkoutRecord {
    @Attribute(.unique) public var startedAt: Date
    public var endedAt: Date?
    public var payload: Data

    public init(startedAt: Date, endedAt: Date?, payload: Data) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.payload = payload
    }
}
