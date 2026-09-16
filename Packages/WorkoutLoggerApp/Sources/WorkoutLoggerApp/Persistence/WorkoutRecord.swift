import Foundation
import SwiftData

/// One persisted workout: the engine's per-session `startedAt` as the natural
/// key, `endedAt` mirrored out for cheap "is a workout still open" checks, and
/// the whole `WorkoutLoggerCore.Workout` value JSON-encoded in `payload`.
/// No `@Attribute(.unique)` (cluster 7a, CloudKit mirroring doesn't support
/// it) -- `SwiftDataWorkoutStore.save` already fetches-then-updates on a
/// matching `startedAt`, so uniqueness was already enforced at the app layer.
/// Defaults below are never actually read (every real instance goes through
/// `init`) -- CloudKit mirroring requires every attribute be optional or
/// carry one, so it can materialize a partially-merged record.
@Model
public final class WorkoutRecord {
    public var startedAt: Date = Date.distantPast
    public var endedAt: Date?
    public var payload: Data = Data()

    public init(startedAt: Date, endedAt: Date?, payload: Data) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.payload = payload
    }
}
