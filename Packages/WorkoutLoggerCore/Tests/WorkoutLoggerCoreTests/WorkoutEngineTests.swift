import Foundation
import Testing
import WorkoutLoggerCore

@Suite("Workout engine")
struct WorkoutEngineTests {

    @Test("starting a workout creates an open workout and persists it")
    func startWorkout() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty)

        engine.startWorkout()

        #expect(engine.workout?.isEnded == false)
        #expect(store.saved.count == 1)
        #expect(store.saved.last?.isEnded == false)
    }

    @Test("hearing an exercise announcement adds an entry for it")
    func announcementAddsEntry() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench press"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()

        engine.hear(["bench press"])

        #expect(engine.workout?.entries.map(\.exercise) == [bench])
        #expect(store.saved.last?.entries.count == 1)
    }

    @Test("hearing a set attaches it to the active entry with the load in kilograms")
    func setAttachesToActiveEntryInKilograms() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench press"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench press"])

        engine.hear(["225 pounds for 5"])

        let sets = engine.workout?.entries.first?.sets
        #expect(sets?.count == 1)
        #expect(sets?.first?.reps == 5)
        #expect(sets?.first?.loadKilograms == 225 * 0.45359237)
    }

    @Test("undo removes the last logged set from the active entry")
    func undoRemovesLastSet() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench press"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench press"])
        engine.hear(["100 for 5"])
        engine.hear(["110 for 3"]) // a distinct set — not a re-speak of the first

        engine.hear(["undo"])

        let sets = engine.workout?.entries.first?.sets
        #expect(sets?.count == 1)
        #expect(sets?.first?.reps == 5)
    }

    @Test("the start-workout and end-workout commands drive the lifecycle by voice")
    func voiceLifecycle() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty)

        engine.hear(["start workout"])
        #expect(engine.workout?.isEnded == false)

        engine.hear(["end workout"])
        #expect(engine.workout?.isEnded == true)
    }

    @Test("a bare set is logged in the engine's unit setting, converted to kilograms")
    func bareSetHonoursUnitSetting() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), unit: .pounds)
        engine.startWorkout()
        engine.hear(["bench"])

        engine.hear(["135 for 5"]) // no spoken unit — falls back to the engine's setting

        #expect(engine.workout?.entries.first?.sets.first?.loadKilograms == 135 * 0.45359237)
    }

    @Test("undo drops a just-announced entry that has no sets yet")
    func undoDropsEmptyEntry() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let squat = Exercise(name: "Squat", aliases: ["squat"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench, squat]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])
        engine.hear(["squat"]) // wrong exercise, no sets logged against it

        engine.hear(["undo"])

        #expect(engine.workout?.entries.map(\.exercise) == [bench])
        #expect(engine.workout?.entries.first?.sets.count == 1)
    }

    @Test("re-announcing an earlier exercise resumes its entry instead of duplicating it")
    func reannouncementResumesEntry() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let squat = Exercise(name: "Squat", aliases: ["squat"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench, squat]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])
        engine.hear(["squat"])
        engine.hear(["140 for 5"])
        engine.hear(["bench"]) // back on the bench for another set

        engine.hear(["100 for 4"])

        #expect(engine.workout?.entries.map(\.exercise) == [bench, squat])
        #expect(engine.workout?.entries.first?.sets.map(\.reps) == [5, 4])
    }

    @Test("undo after resuming an earlier exercise removes that exercise's last set")
    func undoTargetsTheResumedEntry() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let squat = Exercise(name: "Squat", aliases: ["squat"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench, squat]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])
        engine.hear(["squat"])
        engine.hear(["140 for 5"])
        engine.hear(["bench"])
        engine.hear(["100 for 4"])

        engine.hear(["undo"]) // undoes the second bench set, not the squat set

        #expect(engine.workout?.entries.first?.sets.map(\.reps) == [5])
        #expect(engine.workout?.entries.last?.sets.map(\.reps) == [5])
    }

    @Test("saying 'start workout' while one is active closes the previous workout first")
    func startWorkoutMidSessionClosesPrevious() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])

        engine.hear(["start workout"]) // forgot to end the last one

        // the workout now in progress is fresh and empty
        #expect(engine.workout?.isEnded == false)
        #expect(engine.workout?.entries.isEmpty == true)
        // the previous workout was persisted closed, with its logged set intact
        #expect(store.saved.contains { $0.isEnded && $0.entries.first?.sets.count == 1 })
    }

    @Test("sets logged between 'superset' and 'end superset' are grouped as a superset")
    func supersetRunGroupsItsSets() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let row = Exercise(name: "Row", aliases: ["row"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench, row]))
        engine.startWorkout()

        engine.hear(["superset"])
        engine.hear(["bench"])
        engine.hear(["135 for 8"])
        engine.hear(["row"])
        engine.hear(["95 for 8"])
        engine.hear(["bench"]) // alternate back — resumes bench's entry
        engine.hear(["135 for 7"])
        engine.hear(["end superset"])
        engine.hear(["115 for 8"]) // after the run — straight again, still on bench

        let benchSets = engine.workout?.entries.first { $0.exercise == bench }?.sets
        let rowSets = engine.workout?.entries.first { $0.exercise == row }?.sets
        #expect(benchSets?.map(\.grouping) == [.superset, .superset, .straight])
        #expect(rowSets?.map(\.grouping) == [.superset])
    }

    @Test("re-speaking the same set overwrites the last one rather than logging a second")
    func identicalRepeatOverwrites() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])

        engine.hear(["100 for 5"]) // said again — a retry, not a second set

        #expect(engine.workout?.entries.first?.sets.map(\.reps) == [5])
    }

    @Test("a set that matches an earlier one but not the last is still appended")
    func repeatWindowTracksOnlyTheLastSet() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])
        engine.hear(["110 for 5"]) // distinct set — retry window now references this one
        engine.hear(["100 for 5"]) // matches the *first*, not the last — so it appends

        #expect(engine.workout?.entries.first?.sets.map(\.loadKilograms) == [100, 110, 100])
    }

    @Test("re-speaking a set the recogniser misheard corrects it rather than adding one")
    func repeatWithinToleranceCorrects() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 8"]) // recogniser heard "eight" for "five"

        engine.hear(["100 for 5"]) // same load, said again

        #expect(engine.workout?.entries.first?.sets.map(\.reps) == [5])
    }

    @Test("a same-load set with a wildly different rep count is a real second set")
    func repeatOutsideToleranceAppends() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 12"])
        engine.hear(["100 for 5"]) // 7 apart — a back-off set, not a mishearing

        #expect(engine.workout?.entries.first?.sets.map(\.reps) == [12, 5])
    }

    @Test("two superset runs performed back-to-back are recorded as distinct runs")
    func backToBackSupersetsStayDistinct() {
        let exercises = ["a", "b", "c", "d"].map { Exercise(name: $0.uppercased(), aliases: [$0]) }
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary(exercises))
        engine.startWorkout()

        engine.hear(["superset"])
        engine.hear(["a"]); engine.hear(["50 for 10"])
        engine.hear(["b"]); engine.hear(["60 for 10"])
        engine.hear(["end superset"])
        engine.hear(["superset"]) // straight into the next one, no set between
        engine.hear(["c"]); engine.hear(["70 for 10"])
        engine.hear(["d"]); engine.hear(["80 for 10"])
        engine.hear(["end superset"])
        engine.hear(["a"]); engine.hear(["55 for 8"]) // a plain straight set afterwards

        let runID: (String) -> Int? = { name in
            engine.workout?.entries.first { $0.exercise.name == name }?.sets.first?.supersetRunID
        }
        #expect(runID("A") == runID("B"))          // same run
        #expect(runID("C") == runID("D"))          // same run
        #expect(runID("A") != runID("C"))          // different runs
        #expect(runID("A") != nil)
        #expect(engine.workout?.entries.first { $0.exercise.name == "A" }?.sets.last?.supersetRunID == nil) // straight set
    }

    @Test("a fresh workout does not inherit a dangling superset from the last one")
    func supersetFlagResetsOnNewWorkout() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["superset"])
        engine.hear(["bench"])
        engine.hear(["100 for 5"]) // grouped .superset

        engine.startWorkout() // new workout, superset never closed
        engine.hear(["bench"])
        engine.hear(["100 for 5"])

        #expect(engine.workout?.entries.first?.sets.map(\.grouping) == [.straight])
    }

    @Test("the workout and each set carry timestamps from the engine's clock")
    func timestampsAreRecorded() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([bench]),
            now: { clock }
        )

        engine.startWorkout()
        #expect(engine.workout?.startedAt == Date(timeIntervalSince1970: 1_000))
        #expect(engine.workout?.endedAt == nil)

        clock = Date(timeIntervalSince1970: 1_200)
        engine.hear(["bench"])
        engine.hear(["100 for 5"])
        #expect(engine.workout?.entries.first?.sets.first?.loggedAt == Date(timeIntervalSince1970: 1_200))

        clock = Date(timeIntervalSince1970: 5_000)
        engine.endWorkout()
        #expect(engine.workout?.endedAt == Date(timeIntervalSince1970: 5_000))
    }

    @Test("a working set that beats the known best estimated 1RM is a personal record")
    func personalRecordDetected() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([bench]),
            knownBests: ["Bench": 100]
        )
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 3"]) // Epley e1RM = 100 * (1 + 3/30) = 110 > 100

        #expect(engine.personalRecords.map(\.exercise) == [bench])
        #expect(engine.personalRecords.first?.estimatedOneRepMaxKilograms == 110)
    }

    @Test("a warmup set never counts as a personal record")
    func warmupIsNeverAPersonalRecord() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([bench]),
            knownBests: ["Bench": 50]
        )
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["warmup 200 for 1"]) // huge, but a warmup

        #expect(engine.personalRecords.isEmpty)
    }

    @Test("only the first set to reach a new best flags a personal record")
    func personalRecordFlaggedOncePerBest() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([bench]),
            knownBests: ["Bench": 90]
        )
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 3"]) // e1RM 110 — new best → PR
        engine.hear(["95 for 3"])  // e1RM 104.5 — below 110, not a PR
        engine.hear(["105 for 3"]) // e1RM 115.5 — new best → PR

        #expect(engine.personalRecords.count == 2)
        #expect(engine.personalRecords.map(\.estimatedOneRepMaxKilograms) == [110, 115.5])
    }

    @Test("correcting a misheard set does not fire a second personal record")
    func correctionDoesNotRefirePersonalRecord() {
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([bench]),
            knownBests: ["Bench": 90]
        )
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 6"]) // e1RM 120 — a new best → PR
        engine.hear(["100 for 9"]) // recogniser had misheard "nine" as "six"; within tolerance

        // the correction lands, but it is not a fresh celebratory moment
        #expect(engine.workout?.entries.first?.sets.map(\.reps) == [9])
        #expect(engine.personalRecords.count == 1)
        #expect(engine.personalRecords.map(\.estimatedOneRepMaxKilograms) == [120])
    }

    @Test("a correction keeps the original set's timestamp and rest clock")
    func correctionPreservesTiming() {
        var clock = Date(timeIntervalSince1970: 0)
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), now: { clock })
        engine.startWorkout()
        engine.hear(["bench"])
        clock = Date(timeIntervalSince1970: 100)
        engine.hear(["100 for 5"])
        clock = Date(timeIntervalSince1970: 108) // 8s later the lifter re-speaks to fix the rep count
        engine.hear(["100 for 6"])

        #expect(engine.workout?.entries.first?.sets.first?.loggedAt == Date(timeIntervalSince1970: 100))
        #expect(engine.restStartedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("logging a set starts the rest timer counting up from that set")
    func loggingASetStartsTheRestTimer() {
        var clock = Date(timeIntervalSince1970: 0)
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store, library: ExerciseLibrary([bench]),
            restTarget: 90, now: { clock }
        )
        engine.startWorkout()
        engine.hear(["bench"])
        clock = Date(timeIntervalSince1970: 100)
        engine.hear(["100 for 5"])

        clock = Date(timeIntervalSince1970: 160) // 60s past the set
        #expect(engine.restElapsedSeconds == 60)
        #expect(engine.isRestTargetReached == false)

        clock = Date(timeIntervalSince1970: 200) // 100s past the set — over the 90s target
        #expect(engine.isRestTargetReached == true)
    }

    @Test("'skip rest' stops the timer and 'start rest' restarts it from now")
    func startAndSkipRestCommands() {
        var clock = Date(timeIntervalSince1970: 0)
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store, library: ExerciseLibrary([bench]), now: { clock }
        )
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])

        engine.hear(["skip rest"])
        #expect(engine.restElapsedSeconds == nil)

        clock = Date(timeIntervalSince1970: 500)
        engine.hear(["start rest"])
        clock = Date(timeIntervalSince1970: 530)
        #expect(engine.restElapsedSeconds == 30)
    }

    @Test("no rest is running before the first set")
    func noRestBeforeFirstSet() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store, library: .empty, now: { Date(timeIntervalSince1970: 0) }
        )
        engine.startWorkout()

        #expect(engine.restElapsedSeconds == nil)
        #expect(engine.isRestTargetReached == false)
    }

    @Test("an open workout whose last set predates the threshold is stale")
    func staleWorkoutIsDetected() {
        var clock = Date(timeIntervalSince1970: 0)
        let bench = Exercise(name: "Bench", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), now: { clock })
        engine.startWorkout()
        engine.hear(["bench"])
        clock = Date(timeIntervalSince1970: 600) // last set logged 10 min in
        engine.hear(["100 for 5"])
        let workout = try! #require(engine.workout)

        let threeHours: TimeInterval = 3 * 3600
        #expect(workout.isStale(now: Date(timeIntervalSince1970: 4 * 3600), staleAfter: threeHours) == true)
        #expect(workout.isStale(now: Date(timeIntervalSince1970: 3600), staleAfter: threeHours) == false)
    }

    @Test("a workout with no sets falls back to its start time for staleness")
    func stalenessFallsBackToStartTime() {
        let clock = Date(timeIntervalSince1970: 0)
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty, now: { clock })
        engine.startWorkout()
        let workout = try! #require(engine.workout)

        #expect(workout.lastActivityAt == Date(timeIntervalSince1970: 0))
        #expect(workout.isStale(now: Date(timeIntervalSince1970: 7200), staleAfter: 3600) == true)
    }

    @Test("last activity advances to the end time when that is the most recent event")
    func lastActivityCountsTheEndTime() {
        var clock = Date(timeIntervalSince1970: 0)
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty, now: { clock })
        engine.startWorkout()
        clock = Date(timeIntervalSince1970: 3600)
        engine.endWorkout()
        let workout = try! #require(engine.workout)

        #expect(workout.lastActivityAt == Date(timeIntervalSince1970: 3600))
    }

    @Test("an ended workout is never stale")
    func endedWorkoutIsNeverStale() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty, now: { Date(timeIntervalSince1970: 0) })
        engine.startWorkout()
        engine.endWorkout()
        let workout = try! #require(engine.workout)

        #expect(workout.isStale(now: Date(timeIntervalSince1970: 1_000_000), staleAfter: 1) == false)
    }

    @Test("ending a workout closes it and persists the closed revision")
    func endWorkoutCloses() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty)
        engine.startWorkout()

        engine.endWorkout()

        #expect(engine.workout?.isEnded == true)
        #expect(store.saved.last?.isEnded == true)
    }

    // MARK: - resume(_:)

    private func benchWorkout(
        startedAt: Date = Date(timeIntervalSince1970: 0),
        sets: [LoggedSet]
    ) -> Workout {
        Workout(
            entries: [Entry(exercise: Exercise(name: "Barbell Bench Press", aliases: ["bench"]), sets: sets)],
            startedAt: startedAt
        )
    }

    private func workingSet(
        kg: Double, reps: Int, at t: TimeInterval, run: Int? = nil
    ) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: run == nil ? .straight : .superset,
            loadKilograms: kg, reps: reps, supersetRunID: run, loggedAt: Date(timeIntervalSince1970: t)
        )
    }

    @Test("resume adopts an unfinished workout and new sets attach to its last entry")
    func resumeAttachesNewSets() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        let prior = benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)])

        engine.resume(prior)
        engine.hear(["100 for 3"]) // bare set — attaches to the adopted active entry

        #expect(engine.workout?.entries.count == 1)
        #expect(engine.workout?.entries.first?.sets.count == 2)
        #expect(engine.workout?.entries.first?.sets.last?.reps == 3)
        #expect(store.saved.last?.entries.first?.sets.count == 2)
    }

    @Test("resume then undo drops the last pre-existing set")
    func resumeThenUndo() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.resume(benchWorkout(sets: [
            workingSet(kg: 100, reps: 5, at: 10), workingSet(kg: 100, reps: 5, at: 200),
        ]))

        engine.hear(["undo"])

        #expect(engine.workout?.entries.first?.sets.count == 1)
    }

    @Test("resume does not re-celebrate history; a set below the in-workout best is no PR, above it is")
    func resumePersonalRecordBar() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        // existing set: e1RM(100,5) = 100 * 35 / 30 ≈ 116.67
        engine.resume(benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)]))
        #expect(engine.personalRecords.isEmpty)

        engine.hear(["90 for 5"]) // e1RM ≈ 105 — below
        #expect(engine.personalRecords.isEmpty)

        engine.hear(["120 for 5"]) // e1RM = 140 — above
        #expect(engine.personalRecords.count == 1)
        #expect(engine.personalRecords.first?.exercise == bench)
    }

    @Test("resume clears any pre-relaunch rest; rest restarts from the next set")
    func resumeClearsRest() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        var clock = Date(timeIntervalSince1970: 10_000)
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), now: { clock })
        engine.resume(benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)]))

        #expect(engine.restStartedAt == nil)

        clock = Date(timeIntervalSince1970: 10_050)
        engine.hear(["100 for 5"])
        #expect(engine.restStartedAt == Date(timeIntervalSince1970: 10_050))
    }

    @Test("resume numbers a new superset run above any already in the adopted workout")
    func resumeSupersetNumbering() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.resume(benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10, run: 2)]))

        engine.hear(["superset"])
        engine.hear(["100 for 5"])

        #expect(engine.workout?.entries.first?.sets.last?.supersetRunID == 3)
    }

    @Test("a resumed workout ends like any other: endedAt stamped, persisted, no longer open")
    func resumeThenEnd() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        var clock = Date(timeIntervalSince1970: 10_000)
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), now: { clock })
        engine.resume(benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)]))

        clock = Date(timeIntervalSince1970: 12_345)
        engine.endWorkout()

        #expect(engine.workout?.isEnded == true)
        #expect(engine.restStartedAt == nil)
        #expect(store.saved.last?.endedAt == Date(timeIntervalSince1970: 12_345))
        #expect(store.saved.last?.entries.first?.sets.count == 1)
    }

    @Test("resume ignores an already-ended workout")
    func resumeIgnoresEndedWorkout() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty)
        var ended = benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)])
        ended.endedAt = Date(timeIntervalSince1970: 300)

        engine.resume(ended)

        #expect(engine.workout == nil)
        #expect(store.saved.isEmpty)
    }

    @Test("editSet replaces a set in the live workout, persists it, and re-derives the PR bar")
    func editSetLowersPersonalRecordBar() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["120 for 5"])          // e1RM 140 — a personal record, bar now 140
        #expect(engine.personalRecords.count == 1)

        engine.editSet(at: 0, 0, with: LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 60, reps: 5, loggedAt: Date(timeIntervalSince1970: 0)
        ))                                   // e1RM now 70 — bar drops

        #expect(engine.workout?.entries[0].sets[0].loadKilograms == 60)
        #expect(store.saved.last?.entries[0].sets[0].loadKilograms == 60)

        engine.hear(["100 for 5"])           // e1RM 116.67 — above 70, below the stale 140
        #expect(engine.personalRecords.count == 2) // caught, because the bar was re-derived
    }

    @Test("editSet clears the retry target so a re-spoken set does not overwrite the edited row")
    func editSetClearsRetryTarget() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])          // this set becomes the retry target

        engine.editSet(at: 0, 0, with: LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 105, reps: 5, loggedAt: Date(timeIntervalSince1970: 0)
        ))
        engine.hear(["100 for 5"])          // would be a retry-overwrite if the target still stood

        #expect(engine.workout?.entries[0].sets.count == 2) // appended, not overwritten
        #expect(engine.workout?.entries[0].sets.map(\.loadKilograms) == [105, 100])
    }

    @Test("editSet is a no-op with no open workout or an out-of-range index")
    func editSetGuards() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        let dummy = LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 1, reps: 1, loggedAt: Date(timeIntervalSince1970: 0)
        )

        engine.editSet(at: 0, 0, with: dummy)          // no workout yet
        #expect(store.saved.isEmpty)

        engine.startWorkout()
        engine.hear(["bench"])
        engine.hear(["100 for 5"])
        let savesBefore = store.saved.count
        engine.editSet(at: 0, 9, with: dummy)          // set index out of range
        engine.editSet(at: 5, 0, with: dummy)          // entry index out of range
        #expect(store.saved.count == savesBefore)      // nothing persisted
    }
}

/// Test double for `WorkoutStore` — records every persisted revision in order.
final class InMemoryWorkoutStore: WorkoutStore {
    private(set) var saved: [Workout] = []

    func save(_ workout: Workout) {
        saved.append(workout)
    }
}
