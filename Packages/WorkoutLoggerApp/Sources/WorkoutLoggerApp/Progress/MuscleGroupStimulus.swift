import Foundation
import WorkoutLoggerCore

/// The muscle-group taxonomy a per-muscle-group **set volume** is tabulated over
/// (CONTEXT.md "Set volume" — the training-stimulus gauge, distinct from Volume /
/// tonnage). The eleven standard hypertrophy groups (spec 7g-2, Q2).
///
/// The raw value is the group's spelling and becomes the exported key once the
/// per-group export lands (Q8 — deferred for v1.1). `CaseIterable` gives the view
/// a stable display order; `String` raw gives `Codable`/`Hashable` for free.
public enum MuscleGroup: String, CaseIterable, Codable, Sendable, Hashable, Equatable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case quads
    case hamstrings
    case glutes
    case calves
    case core
    case forearms

      /// "Chest", "Back", … — the raw spelling capitalised for display.
    public var displayName: String { rawValue.capitalized }
}

/// The per-muscle-group working-set count over a window, plus the working sets
/// whose exercise the map doesn't know. `total` reconciles: it is the sum of the
/// per-group counts and the unclassified bucket, and equals the whole-workout
/// set volume over the same window — the invariant the "unclassified" row keeps
/// (spec 7g-2, Q5).
public struct MuscleGroupSetVolume: Equatable, Sendable {
      /// Working sets attributed to each known group this window. A group with no
      /// sets is absent.
    public let perGroup: [MuscleGroup: Int]
      /// Working sets whose exercise the `MuscleMap` doesn't map — the row that
      /// keeps `total` reconciling.
    public let unclassified: Int

      /// Σ per-group counts + the unclassified bucket.
    public var total: Int { perGroup.values.reduce(0, +) + unclassified }

    public init(perGroup: [MuscleGroup: Int], unclassified: Int = 0) {
        self.perGroup = perGroup
        self.unclassified = unclassified
       }
}

/// The exercise→muscle-group mapping. Keyed by exercise **name** (lowercased,
/// trimmed) rather than the whole `Exercise` value: `Exercise` is
/// alias-order-sensitive (`Model.swift`), so name-keying is the robust seam, and
/// the built-in seed is a name-keyed table anyway.
public struct MuscleMap: Equatable, Sendable {
      /// Lowercased, trimmed exercise name → the groups its sets count toward.
    private let byName: [String: [MuscleGroup]]

    public init(mappings: [String: [MuscleGroup]]) {
        var table: [String: [MuscleGroup]] = [:]
        for (name, groups) in mappings {
            table[Self.key(for: name)] = groups
          }
        self.byName = table
       }

      /// The groups one exercise's sets count toward, by its name, or `[]` when
      /// the exercise isn't mapped. Case- and whitespace-insensitive.
    public func groups(forExerciseNamed name: String) -> [MuscleGroup] {
        byName[Self.key(for: name)] ?? []
       }

      /// The groups an `Exercise`'s sets count toward (by its display name).
    public func groups(for exercise: Exercise) -> [MuscleGroup] {
        groups(forExerciseNamed: exercise.name)
       }

    private static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
       }
}

extension MuscleMap {
      /// The per-muscle-group set volume across `history` that fell in `window`.
      ///
      /// A workout belongs to the window by its `startedAt`. Each workout's
      /// per-exercise working-set count (Core's `workoutSetVolumeByExercise(_:)`
      /// — warmups excluded, a superset / dropset round counting one per working
      /// entry, a timed / distance working set still counting) is attributed
      /// **flat 1.0** to every group the exercise's name maps to (spec 7g-2, Q4).
      /// An exercise the map doesn't know lands its count in `unclassified` so the
      /// total reconciles (Q5).
    public func setVolume(across history: [Workout], in window: DateInterval)
        -> MuscleGroupSetVolume {
        var perGroup: [MuscleGroup: Int] = [:]
        var unclassified = 0
        for workout in history where window.contains(workout.startedAt) {
            for (exercise, count) in workoutSetVolumeByExercise(workout) {
                let groups = groups(for: exercise)
                if groups.isEmpty {
                    unclassified += count
                  } else {
                    for group in groups {
                        perGroup[group, default: 0] += count
                       }
                    }
               }
            }
        return MuscleGroupSetVolume(perGroup: perGroup, unclassified: unclassified)
       }
}

/// The Monday-start calendar week (spec 7g-2 Q6) containing `date`, computed in
/// `calendar`'s time zone. The start is the Monday 00:00 of that week; the end is
/// seven days on. A rolling-7-day window is a one-line swap.
///
/// This derives the Monday from the date's own weekday component rather than the
/// calendar's `firstWeekday`, so it is independent of how the caller configured
/// the calendar. Foundation numbers weekdays 1 = Sunday … 7 = Saturday; the days
/// back to the Monday of the week are `(weekday + 5) % 7` (Mon→0, Tue→1, …,
/// Sat→5, Sun→6).
public func calendarWeek(containing date: Date, in calendar: Calendar) -> DateInterval {
    let weekday = calendar.component(.weekday, from: date)
    let daysFromMonday = (weekday + 5) % 7
    let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
     // The SDK's Calendar has no startingOfDay, so floor the Monday to midnight
     // by rebuilding it from the day components (the idiom WorkoutHistoryExport uses).
    let start = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: monday)) ?? monday
    let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
    return DateInterval(start: start, end: end)
}

/// The mapping the app ships with — the six built-in starters (Q2), each to the
/// groups it predominantly trains. Flat attribution (Q4): every listed group gets
/// the full count. Custom exercises (not yet pickable, see the 7g-2 follow-up)
/// aren't here — they resolve to no groups and land in `unclassified`.
public let defaultMuscleMap = MuscleMap(mappings: [
    "Barbell Bench Press": [.chest, .triceps, .shoulders],
    "Barbell Back Squat": [.quads, .glutes, .core],
    "Conventional Deadlift": [.back, .hamstrings, .forearms],
    "Overhead Press": [.shoulders, .triceps],
    "Barbell Row": [.back, .biceps],
    "Pull-Up": [.back, .biceps],
])
