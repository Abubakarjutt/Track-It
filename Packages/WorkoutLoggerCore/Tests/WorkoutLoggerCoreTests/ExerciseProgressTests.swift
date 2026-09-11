import Foundation
import Testing
import WorkoutLoggerCore

@Suite("Exercise progress")
struct ExerciseProgressTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])
    private let squat = Exercise(name: "Squat", aliases: ["squat"])

    private func workout(
        startedAt: Date,
        _ sets: [LoggedSet],
        exercise: Exercise? = nil,
        endedAt: Date? = nil
    ) -> Workout {
        Workout(
            entries: [Entry(exercise: exercise ?? bench, sets: sets)],
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    private func workingSet(load: Double, reps: Int) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func warmupSet(load: Double, reps: Int) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: .reps, role: .warmup, grouping: .straight,
            loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("one workout's working sets fold into a single session with summed volume")
    func singleSessionVolume() {
        let day = Date(timeIntervalSince1970: 1_000)
        let history = [
            workout(startedAt: day, [
                workingSet(load: 100, reps: 5), // 500
                workingSet(load: 100, reps: 5), // 500
                workingSet(load: 90, reps: 8),  // 720
            ])
        ]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.sessions.count == 1)
        #expect(progress.sessions.first?.date == day)
        #expect(progress.sessions.first?.volumeKilograms == 1_720)
    }

    @Test("sessions follow the history order, and workouts without the exercise are skipped")
    func multipleSessionsInOrderSkippingAbsentWorkouts() {
        let week1 = Date(timeIntervalSince1970: 1_000)
        let week2 = Date(timeIntervalSince1970: 2_000)
        let week3 = Date(timeIntervalSince1970: 3_000)
        let history = [
            workout(startedAt: week1, [workingSet(load: 100, reps: 5)]),                  // bench — 500
            workout(startedAt: week2, [workingSet(load: 140, reps: 5)], exercise: squat), // squat only
            workout(startedAt: week3, [workingSet(load: 105, reps: 5)]),                  // bench — 525
        ]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.sessions.map(\.date) == [week1, week3])
        #expect(progress.sessions.map(\.volumeKilograms) == [500, 525])
    }

    @Test("the top set is the heaviest working set's load, ignoring warmups")
    func topSetLoad() {
        let day = Date(timeIntervalSince1970: 1_000)
        let history = [
            workout(startedAt: day, [
                warmupSet(load: 140, reps: 3),  // heaviest bar overall — but a warmup
                workingSet(load: 100, reps: 5),
                workingSet(load: 110, reps: 3), // heaviest working set
                workingSet(load: 105, reps: 4),
            ])
        ]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.sessions.first?.topSetLoadKilograms == 110)
    }

    @Test("a session sums its working reps, so loadless work still shows progression")
    func sessionWorkingReps() {
        let day = Date(timeIntervalSince1970: 1_000)
        func pullup(_ reps: Int) -> LoggedSet {
            LoggedSet(
                loadType: .bodyweight, effort: .reps, role: .working, grouping: .straight,
                reps: reps, loggedAt: Date(timeIntervalSince1970: 0)
            )
        }
        let history = [
            workout(startedAt: day, [warmupSet(load: 40, reps: 5), pullup(10), pullup(8), pullup(6)])
        ]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.sessions.first?.volumeKilograms == 0)   // no external load — tonnage is zero
        #expect(progress.sessions.first?.workingReps == 24)       // 10 + 8 + 6; the warmup's 5 do not count
    }

    @Test("a session with only bodyweight working sets has no top set load")
    func topSetLoadNilWithoutLoadedSets() {
        let day = Date(timeIntervalSince1970: 1_000)
        let bodyweight = LoggedSet(
            loadType: .bodyweight, effort: .reps, role: .working, grouping: .straight,
            reps: 12, loggedAt: Date(timeIntervalSince1970: 0)
        )
        let history = [workout(startedAt: day, [bodyweight])]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.sessions.first?.topSetLoadKilograms == nil)
    }

    @Test("a session's best estimated 1RM is the highest Epley estimate over its working sets")
    func sessionBestEstimatedOneRepMax() {
        let day = Date(timeIntervalSince1970: 1_000)
        let history = [
            workout(startedAt: day, [
                warmupSet(load: 60, reps: 5),
                workingSet(load: 100, reps: 3), // Epley 100 * 33/30 = 110
                workingSet(load: 105, reps: 3), // Epley 105 * 33/30 = 115.5
                workingSet(load: 120, reps: 2), // Epley 120 * 32/30 = 128 — the best
            ])
        ]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.sessions.first?.bestEstimatedOneRepMaxKilograms == 128)
    }

    @Test("a session with no working rep set has no estimated 1RM")
    func sessionEstimatedOneRepMaxNilWithoutRepSets() {
        let day = Date(timeIntervalSince1970: 1_000)
        let timed = LoggedSet(
            loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
            durationSeconds: 60, loggedAt: Date(timeIntervalSince1970: 0)
        )
        let history = [workout(startedAt: day, [timed])]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.sessions.first?.bestEstimatedOneRepMaxKilograms == nil)
    }

    @Test("the all-time best estimated 1RM is the highest across every session")
    func allTimeBestEstimatedOneRepMax() {
        let history = [
            workout(startedAt: Date(timeIntervalSince1970: 1_000), [workingSet(load: 100, reps: 3)]), // 110
            workout(startedAt: Date(timeIntervalSince1970: 2_000), [workingSet(load: 105, reps: 3)]), // 115.5
            workout(startedAt: Date(timeIntervalSince1970: 3_000), [workingSet(load: 100, reps: 3)]), // 110
        ]

        let progress = exerciseProgress(for: bench, across: history)

        #expect(progress.bestEstimatedOneRepMaxKilograms == 115.5)
    }

    @Test("an exercise never trained for reps has no all-time best estimated 1RM")
    func allTimeBestEstimatedOneRepMaxNil() {
        let progress = exerciseProgress(for: bench, across: [])

        #expect(progress.bestEstimatedOneRepMaxKilograms == nil)
    }


    // MARK: - Set volume (cluster 7g-1)

    @Test("a session's working set count excludes warmups and counts timed / distance / bodyweight work")
    func workingSetCountExcludesWarmupsAndCountsTimedAndBodyweight() {
        let day = Date(timeIntervalSince1970: 1_000)
        let timed = LoggedSet(
            loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
            durationSeconds: 60, loggedAt: Date(timeIntervalSince1970: 0))
        let bodyweight = LoggedSet(
            loadType: .bodyweight, effort: .reps, role: .working, grouping: .straight,
            reps: 12, loggedAt: Date(timeIntervalSince1970: 0))
        let history = [
            workout(startedAt: day, [
                warmupSet(load: 40, reps: 5),   // excluded
                workingSet(load: 100, reps: 5), // 1 — external
                timed,                           // 1 — a working timed set still counts
                bodyweight,                      // 1 — a working bodyweight set still counts
                warmupSet(load: 100, reps: 2),  // excluded
             ])
         ]

        let session = exerciseProgress(for: bench, across: history).sessions.first

         #expect(session?.workingSetCount == 3)
         #expect(session?.workingReps == 17)        // 5 + 12; the timed set carries no reps
         #expect(session?.volumeKilograms == 500)   // 100 × 5; bodyweight / timed add no tonnage
     }

    @Test("workoutSetVolume counts every working set across all exercises, ignoring warmups")
    func workoutSetVolumeCountsWorkingSetsAcrossExercises() {
        let w = Workout(
            entries: [
                Entry(exercise: bench, sets: [
                    workingSet(load: 100, reps: 5),
                    workingSet(load: 110, reps: 3),
                    warmupSet(load: 60, reps: 2),
                 ]),
                Entry(exercise: squat, sets: [
                    workingSet(load: 140, reps: 3),
                    workingSet(load: 150, reps: 3),
                 ]),
             ],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 600)
         )

         #expect(workoutSetVolume(w) == 4)   // 2 bench + 2 squat; the warmup is excluded
     }

    @Test("workoutSetVolumeByExercise keys the per-exercise count by the whole exercise value")
    func workoutSetVolumeByExerciseKeysByValue() {
        let w = Workout(
            entries: [
                Entry(exercise: bench, sets: [
                    workingSet(load: 100, reps: 5),
                    workingSet(load: 110, reps: 3),
                    warmupSet(load: 60, reps: 2),
                 ]),
                Entry(exercise: squat, sets: [
                    workingSet(load: 140, reps: 3),
                    workingSet(load: 150, reps: 3),
                 ]),
                Entry(exercise: bench, sets: [workingSet(load: 120, reps: 2)]),   // a second bench entry merges
             ],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 600)
         )

        let counts = workoutSetVolumeByExercise(w)

         #expect(counts[bench] == 3)                       // 2 + 1
         #expect(counts[squat] == 2)
         #expect(counts.count == 2)
         #expect(workoutSetVolume(w) == counts.values.reduce(0, +))   // the two views agree: 5
     }

    @Test("a superset round counts one set per working entry, not one per round")
    func supersetRoundCountsPerEntry() {
        func superset(_ run: Int, _ load: Double, _ reps: Int) -> LoggedSet {
            LoggedSet(
                loadType: .external, effort: .reps, role: .working, grouping: .superset,
                loadKilograms: load, reps: reps, supersetRunID: run, loggedAt: Date(timeIntervalSince1970: 0)
             )
         }
        let w = Workout(
            entries: [
                Entry(exercise: bench, sets: [
                    superset(1, 100, 5),
                    superset(1, 110, 3),
                 ]),
                Entry(exercise: squat, sets: [
                    superset(1, 80, 5),
                    superset(1, 90, 4),
                 ]),
             ],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 600)
         )

         #expect(workoutSetVolume(w) == 4)   // four working entries → four sets, not two rounds
     }

    @Test("a warmup-only or empty workout has no set volume")
    func emptyOrWarmupOnlyWorkoutHasNoSetVolume() {
        let warmups = Workout(
            entries: [Entry(exercise: bench, sets: [
                warmupSet(load: 60, reps: 2),
                warmupSet(load: 80, reps: 2),
             ])],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60)
         )
         #expect(workoutSetVolume(warmups) == 0)
         #expect(workoutSetVolumeByExercise(warmups).isEmpty)

        let empty = Workout(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60))
         #expect(workoutSetVolume(empty) == 0)
         #expect(workoutSetVolumeByExercise(empty).isEmpty)
     }
}
