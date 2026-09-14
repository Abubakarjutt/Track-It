import Foundation
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("MuscleGroupStimulus")
struct MuscleGroupStimulusTests {

    // MARK: - Fixtures

    private let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"])
    private let squat = Exercise(name: "Barbell Back Squat", aliases: ["squat"])
    private let curl = Exercise(name: "Barbell Curl", aliases: ["curl"])     // not in the seed map
    private let pullup = Exercise(name: "Pull-Up", aliases: ["pull up"])

    private func working(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }
    private func warmup(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .warmup, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }
    private func timed() -> LoggedSet {
        LoggedSet(loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
                  durationSeconds: 60, loggedAt: Date(timeIntervalSince1970: 0))
    }

    /// A single-entry, single-exercise workout that started `started` seconds
    /// after the 1970 epoch and ended `duration` seconds later.
    private func workout(_ started: TimeInterval, _ exercise: Exercise, _ sets: [LoggedSet],
                         duration: TimeInterval = 600) -> Workout {
        Workout(entries: [Entry(exercise: exercise, sets: sets)],
                startedAt: Date(timeIntervalSince1970: started),
                endedAt: Date(timeIntervalSince1970: started + duration))
    }

    /// A UTC Gregorian calendar — deterministic week arithmetic, no DST.
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A window that contains every workout — the SDK has no `DateInterval.infinity`,
    /// but `Date.distantPast` / `.distantFuture` do (see `TelemetryUploader`).
    private static let allTime = DateInterval(start: .distantPast, end: .distantFuture)

    // MARK: - Task 1: the lookup

    @Test("the seed map covers the six built-in starters with their groups")
    func defaultMapCoversStarters() {
        let map = defaultMuscleMap
        #expect(map.groups(for: bench).contains(.chest))
        #expect(map.groups(for: bench).contains(.triceps))
        #expect(map.groups(for: bench).contains(.shoulders))
        #expect(map.groups(for: squat).contains(.quads))
        #expect(map.groups(for: pullup).contains(.back))
    }

    @Test("group lookup is case- and whitespace-insensitive over the exercise name")
    func lookupIsNameInsensitive() {
        let map = defaultMuscleMap
        // The map is keyed by the exercise *name* (not its aliases), so the
        // insensitivity is proven with the actual key in varied case / spacing.
        #expect(map.groups(forExerciseNamed: "  bArBeLL BEnCh pReSs   ")
                == map.groups(forExerciseNamed: "Barbell Bench Press"))
        #expect(!map.groups(forExerciseNamed: "  BARBELL BENCH PRESS   ").isEmpty)
        #expect(map.groups(forExerciseNamed: "Barbell Bench Press").contains(.chest))
    }

    @Test("an exercise the map does not know resolves to no groups")
    func unknownExerciseHasNoGroups() {
        let map = defaultMuscleMap
        #expect(map.groups(for: curl).isEmpty)
    }

    // MARK: - Task 2: the fold

    @Test("a compound lift's working sets attribute flat to every group its name maps to")
    func flatAttribution() {
        let map = defaultMuscleMap
        let history = [
            workout(1_000, bench, [working(100, 5), working(110, 3), working(120, 1)]),
        ]
        // three bench working sets, each counting to chest + triceps + shoulders
        let v = map.setVolume(across: history, in: Self.allTime)

        #expect(v.perGroup[.chest] == 3)
        #expect(v.perGroup[.triceps] == 3)
        #expect(v.perGroup[.shoulders] == 3)
        #expect(v.perGroup[.quads] == nil)     // squat-less week
        #expect(v.unclassified == 0)
        #expect(v.total == 9)                   // 3 sets × 3 groups
    }

    @Test("an unmapped exercise's working sets land in 'unclassified', and total still reconciles")
    func unclassifiedBucketReconciles() {
        let map = defaultMuscleMap
        let history = [
            workout(1_000, bench, [working(100, 5), working(110, 3)]),
            workout(2_000, curl, [working(30, 10)]),
        ]
        let v = map.setVolume(across: history, in: Self.allTime)

        #expect(v.perGroup[.chest] == 2)
        #expect(v.perGroup[.shoulders] == 2)
        #expect(v.unclassified == 1)
        #expect(v.total == 7)     // 2×3 + 1
        #expect(v.total == v.perGroup.values.reduce(0, +) + v.unclassified)     // the invariant
    }

    @Test("unmapped volume reconciles with Core's set volume; flat sets fan out to every group")
    func totalReconcilesWithCoreSetVolume() {
        let map = defaultMuscleMap
        let history = [
            workout(1_000, bench, [working(100, 5), working(110, 3)]),                  // 2 → 3 groups
            workout(2_000, squat, [working(140, 3), working(150, 3), working(160, 1)]), // 3 → 3 groups
            workout(3_000, curl, [working(30, 10)]),                                   // 1 → unmapped
        ]
        let v = map.setVolume(across: history, in: Self.allTime)

        // The one exercise the map doesn't know (curl) drops its Core working-set
        // volume into 'unclassified' — a direct cross-check against the Core rollup.
        let unmappedCoreVolume = history
            .filter { map.groups(for: $0.entries[0].exercise).isEmpty }
            .reduce(0) { $0 + workoutSetVolume($1) }
        #expect(v.unclassified == unmappedCoreVolume)        // == 1

        // total reconciles as the per-group side plus the unclassified bucket …
        #expect(v.total == v.perGroup.values.reduce(0, +) + v.unclassified)
        // … and, with flat 1.0 attribution, exceeds the raw working-set count
        // (each compound set is counted once per group its name maps to).
        let rawWorkingSets = history.reduce(0) { $0 + workoutSetVolume($1) }   // 2 + 3 + 1 = 6
        #expect(v.total > rawWorkingSets)                            // 16 > 6
    }

    @Test("warmups are excluded; timed / distance working sets still count")
    func warmupsExcludedTimedCounts() {
        let map = defaultMuscleMap
        let history = [
            workout(1_000, bench, [warmup(60, 3), warmup(80, 2), working(100, 5), timed()]),
        ]
        let v = map.setVolume(across: history, in: Self.allTime)

        // two working sets (one external, one timed) × {chest, triceps, shoulders}
        #expect(v.perGroup[.chest] == 2)
        #expect(v.total == 6)
        #expect(v.unclassified == 0)
    }

    @Test("a two-exercise superset round counts one set per working entry, not one per round")
    func supersetCountsPerEntry() {
        func superset(_ run: Int, _ load: Double, _ reps: Int) -> LoggedSet {
            LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .superset,
                      loadKilograms: load, reps: reps, supersetRunID: run,
                      loggedAt: Date(timeIntervalSince1970: 0))
        }
        // One round, two working entries, two different compound lifts.
        let history = [
            workout(1_000, bench, [superset(1, 100, 5)]),      // chest/triceps/shoulders
            workout(1_000, squat, [superset(1, 120, 5)]),      // quads/glutes/core
        ]
        let v = defaultMuscleMap.setVolume(across: history, in: Self.allTime)

        // One set per *working entry*: each lift's single entry lands once in its
        // groups (a whole round would collapse to a single set, not one per entry).
        #expect(v.perGroup[.chest] == 1)
        #expect(v.perGroup[.quads] == 1)
        // Flat attribution fans each entry to its groups, so the total is the fan-out.
        #expect(v.total == 6)       // 2 entries × 3 groups
    }

    @Test("only workouts whose start falls in the window count")
    func windowingByStart() {
        let map = defaultMuscleMap
        let week1 = workout(1_000, bench, [working(100, 5)])                  // t = 1000 s, in the window
        let week2 = workout(1_000 + 14 * 24 * 3600, bench, [working(110, 5)]) // two weeks on, outside
        let window = DateInterval(start: Date(timeIntervalSince1970: 1000),
                                  duration: 7 * 24 * 3600)

        #expect(map.setVolume(across: [week1, week2], in: window).total == 3)       // only week1
        #expect(map.setVolume(across: [week1, week2], in: Self.allTime).total == 6)  // both
    }

    // MARK: - Task 3: the window

    @Test("calendarWeek returns the Monday-start week containing the date")
    func mondayStartWeek() {
        // 2026-01-05 is a Monday; 2026-01-04 is the Sunday of the prior week;
        // 2026-01-07 is the Wednesday of the 5th's week.
        let wednesday = date(2026, 1, 7, hour: 9)
        let sunday = date(2026, 1, 4, hour: 6)
        let monday = date(2026, 1, 5, hour: 12)
        let mondayOf5th = date(2026, 1, 5, hour: 0)
        let mondayOf29th = date(2025, 12, 29, hour: 0)

        #expect(calendarWeek(containing: wednesday, in: utc).start == mondayOf5th)
        // a Sunday sits in the *prior* Monday-start week
        #expect(calendarWeek(containing: sunday, in: utc).start == mondayOf29th)
        #expect(calendarWeek(containing: monday, in: utc).start == mondayOf5th)
        // each week spans exactly seven days
        let week = calendarWeek(containing: monday, in: utc)
        #expect(week.end.timeIntervalSince(week.start) == 7 * 86_400)
    }

    @Test("a workout straddling the week boundary is owned by its start's week")
    func boundaryOwnedByStart() {
        // A workout that starts late in week A but ends in week B counts toward A.
        let start = date(2026, 1, 4, hour: 23)     // Sunday night, week of 2025-12-29
        let long = workout(start.timeIntervalSince1970, bench, [working(100, 5)],
                           duration: 48 * 3600)    // 48 h → ends mid next week
        let thisWeek = calendarWeek(containing: start, in: utc)
        let nextWeek = calendarWeek(containing: start.addingTimeInterval(36 * 3600), in: utc)

        #expect(defaultMuscleMap.setVolume(across: [long], in: thisWeek).total == 3)
        #expect(defaultMuscleMap.setVolume(across: [long], in: nextWeek).total == 0)
    }
}
