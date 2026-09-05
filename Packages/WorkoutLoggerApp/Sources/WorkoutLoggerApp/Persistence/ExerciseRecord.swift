import SwiftData

/// One persisted Exercise in the user's library: a unique canonical name and
/// its spoken aliases. Distinct from `WorkoutRecord` in the same container —
/// "delete all workout data" removes `WorkoutRecord`s only.
@Model
public final class ExerciseRecord {
    @Attribute(.unique) public var name: String
    public var aliases: [String]

    public init(name: String, aliases: [String]) {
        self.name = name
        self.aliases = aliases
    }
}
