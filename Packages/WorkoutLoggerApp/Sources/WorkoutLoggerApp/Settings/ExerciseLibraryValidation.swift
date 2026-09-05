import WorkoutLoggerCore

/// The Exercise-library naming rule, enforced at the `SettingsModel` seam
/// (spec: "trimmed non-empty, and not equal (case-insensitive) to another
/// Exercise's name. Enforced at the model seam"). The stores below are plain
/// persistence and trust the `Exercise` they are handed, so this is the one
/// place the rule lives — for both the SwiftData and in-memory stores.
public enum ExerciseLibraryValidation {

    /// Trim `name`, check it against `existing`, and return the cleaned
    /// `Exercise` to persist — or throw `ExerciseLibraryError`.
    ///
    /// `renaming` is the current name of the record being edited, if any: it
    /// does not count as a collision with itself, so a case-only rename or an
    /// alias-only edit passes.
    public static func validated(
        name: String,
        aliases: [String],
        against existing: [Exercise],
        renaming currentName: String? = nil
    ) throws -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExerciseLibraryError.emptyName }

        let collides = existing.contains { other in
            if let currentName,
               other.name.localizedCaseInsensitiveCompare(currentName) == .orderedSame {
                return false
            }
            return other.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !collides else { throw ExerciseLibraryError.duplicateName }

        return Exercise(name: trimmed, aliases: aliases)
    }
}
