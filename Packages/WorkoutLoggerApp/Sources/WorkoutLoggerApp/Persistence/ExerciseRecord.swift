import SwiftData

/// One persisted Exercise in the user's library: a canonical name and its
/// spoken aliases. Distinct from `WorkoutRecord` in the same container —
/// "delete all workout data" removes `WorkoutRecord`s only. No
/// `@Attribute(.unique)` on `name` (cluster 7a, CloudKit mirroring doesn't
/// support it) -- case-insensitive uniqueness is enforced one level up at
/// `ExerciseLibraryValidation` for same-device adds, and
/// `SwiftDataExerciseLibraryStore.all()` merges any cross-device
/// near-duplicate at read time. Defaults below are never actually read
/// (every real instance goes through `init`) -- CloudKit mirroring requires
/// every attribute be optional or carry one.
@Model
public final class ExerciseRecord {
    public var name: String = ""
    public var aliases: [String] = []

    public init(name: String, aliases: [String]) {
        self.name = name
        self.aliases = aliases
    }
}
