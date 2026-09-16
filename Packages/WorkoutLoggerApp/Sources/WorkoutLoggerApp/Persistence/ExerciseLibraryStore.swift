import Foundation
import SwiftData
import WorkoutLoggerCore

public enum ExerciseLibraryError: Error, Equatable {
    case emptyName
    case duplicateName
}

/// Plain persistence for the user's Exercise library. The naming rule
/// (trimmed non-empty, case-insensitively unique) is enforced one level up
/// at the `SettingsModel` seam via `ExerciseLibraryValidation`; these
/// methods trust the `Exercise` they are handed.
public protocol ExerciseLibraryStore: AnyObject {
    /// Every Exercise, sorted alphabetically by name (case-insensitive).
    func all() -> [Exercise]
    /// Insert `exercises` only when the store is currently empty.
    func seedIfEmpty(_ exercises: [Exercise])
    /// Store `exercise` as a new record.
    func add(_ exercise: Exercise)
    /// Replace the record currently named `originalName` with `exercise`.
    /// No-op if `originalName` is absent.
    func update(named originalName: String, to exercise: Exercise)
    /// Remove the exercise named `name`. No-op if absent.
    func delete(named name: String)
}

/// The exercises a brand-new install starts with. After first launch the
/// library is entirely user-owned; this is only the initial population.
public let defaultExerciseSeed: [Exercise] = [
    Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"]),
    Exercise(name: "Barbell Back Squat", aliases: ["squat", "squats", "back squat"]),
    Exercise(name: "Conventional Deadlift", aliases: ["deadlift", "deads"]),
    Exercise(name: "Overhead Press", aliases: ["ohp", "overhead press", "press"]),
    Exercise(name: "Barbell Row", aliases: ["row", "barbell row", "bent row"]),
    Exercise(name: "Pull-Up", aliases: ["pull up", "pull ups", "pullups"]),
]

/// SwiftData-backed `ExerciseLibraryStore`. One `ExerciseRecord` per Exercise.
public final class SwiftDataExerciseLibraryStore: ExerciseLibraryStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    private func records() -> [ExerciseRecord] {
        (try? context.fetch(FetchDescriptor<ExerciseRecord>())) ?? []
    }

    /// Merges any raw records left case-insensitively-duplicate by a
    /// not-yet-reconciled cross-device sync (cluster 7a) into one `Exercise`
    /// per name, unioning their aliases. `add`/`update`/`delete` still
    /// operate on the raw, unmerged `records()`. `FetchDescriptor` makes no
    /// ordering guarantee, so records are sorted (plain `<`, case-sensitive)
    /// before merging -- otherwise which duplicate's casing "wins" as the
    /// canonical name would vary run to run.
    public func all() -> [Exercise] {
        var merged: [String: Exercise] = [:]  // keyed by lowercased name
        for record in records().sorted(by: { $0.name < $1.name }) {
            let key = record.name.lowercased()
            if let existing = merged[key] {
                merged[key] = Exercise(
                    name: existing.name,
                    aliases: Array(Set(existing.aliases + record.aliases))
                )
            } else {
                merged[key] = Exercise(name: record.name, aliases: record.aliases)
            }
        }
        return merged.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func seedIfEmpty(_ exercises: [Exercise]) {
        guard records().isEmpty else { return }
        for exercise in exercises {
            context.insert(ExerciseRecord(name: exercise.name, aliases: exercise.aliases))
        }
        try? context.save()
    }

    public func add(_ exercise: Exercise) {
        context.insert(ExerciseRecord(name: exercise.name, aliases: exercise.aliases))
        try? context.save()
    }

    public func update(named originalName: String, to exercise: Exercise) {
        guard let record = records().first(where: {
            $0.name.localizedCaseInsensitiveCompare(originalName) == .orderedSame
        }) else { return }
        record.name = exercise.name
        record.aliases = exercise.aliases
        try? context.save()
    }

    public func delete(named name: String) {
        for record in records()
        where record.name.localizedCaseInsensitiveCompare(name) == .orderedSame {
            context.delete(record)
        }
        try? context.save()
    }
}
