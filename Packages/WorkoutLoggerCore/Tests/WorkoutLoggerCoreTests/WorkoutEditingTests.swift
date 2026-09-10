import Foundation
import Testing
import WorkoutLoggerCore

@Suite("Post-workout editing")
struct WorkoutEditingTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])

    private func set(load: Double, reps: Int) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func workout(_ sets: [LoggedSet]) -> Workout {
        Workout(
            entries: [Entry(exercise: bench, sets: sets)],
            startedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private let squat = Exercise(name: "Squat", aliases: ["squat"])

    private func warmup(load: Double, reps: Int) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: .reps, role: .warmup, grouping: .straight,
            loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("replacing a set swaps it in place and leaves the others alone")
    func replacingASet() {
        let original = workout([set(load: 100, reps: 5), set(load: 100, reps: 5), set(load: 100, reps: 5)])

        let edited = original.replacingSet(at: 0, 1, with: set(load: 90, reps: 8))

        #expect(edited.entries[0].sets.map(\.reps) == [5, 8, 5])
        #expect(edited.entries[0].sets.map(\.loadKilograms) == [100, 90, 100])
    }

    @Test("replacing a set at an out-of-range index changes nothing")
    func replacingOutOfRangeIsNoOp() {
        let original = workout([set(load: 100, reps: 5)])

        #expect(original.replacingSet(at: 0, 3, with: set(load: 1, reps: 1)) == original)
        #expect(original.replacingSet(at: 2, 0, with: set(load: 1, reps: 1)) == original)
    }

    @Test("removing a set drops just that set when the entry still has others")
    func removingOneOfSeveralSets() {
        let original = workout([set(load: 100, reps: 5), set(load: 110, reps: 3), set(load: 105, reps: 4)])

        let edited = original.removingSet(at: 0, 1)

        #expect(edited.entries.count == 1)
        #expect(edited.entries[0].sets.map(\.loadKilograms) == [100, 105])
    }

    @Test("removing the last set of an entry drops the entry too")
    func removingLastSetDropsEntry() {
        let original = Workout(
            entries: [
                Entry(exercise: bench, sets: [set(load: 100, reps: 5)]),
                Entry(exercise: squat, sets: [set(load: 140, reps: 5)]),
            ],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        let edited = original.removingSet(at: 0, 0)

        #expect(edited.entries.map(\.exercise) == [squat])
    }

    @Test("removing a set at an out-of-range index changes nothing")
    func removingOutOfRangeIsNoOp() {
        let original = workout([set(load: 100, reps: 5)])

        #expect(original.removingSet(at: 0, 4) == original)
        #expect(original.removingSet(at: 3, 0) == original)
    }

    @Test("saving a workout as a template keeps exercises in order with their working-set counts")
    func templateFromWorkout() {
        let source = Workout(
            entries: [
                Entry(exercise: bench, sets: [
                    warmup(load: 60, reps: 5), set(load: 100, reps: 5),
                    set(load: 100, reps: 5), set(load: 100, reps: 4),
                ]),
                Entry(exercise: squat, sets: [set(load: 140, reps: 5), set(load: 140, reps: 5)]),
            ],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        let template = workoutTemplate(from: source, named: "Wednesday")

        #expect(template.name == "Wednesday")
        #expect(template.items.map(\.exercise) == [bench, squat])
        #expect(template.items.map(\.plannedSets) == [3, 2]) // warmup does not count
        #expect(template.items.allSatisfy { $0.restTargetSeconds == nil })
    }

    @Test("a workout and its individual sets can carry freeform notes")
    func annotating() {
        let original = workout([set(load: 100, reps: 5), set(load: 100, reps: 5)])

        let edited = original
            .annotated(with: "Felt strong, bumped the top set")
            .annotatingSet(at: 0, 1, with: "left elbow twinge")

        #expect(edited.note == "Felt strong, bumped the top set")
        #expect(edited.entries[0].sets.map(\.note) == [nil, "left elbow twinge"])
    }

    @Test("annotating a set at an out-of-range index changes nothing")
    func annotatingOutOfRangeIsNoOp() {
        let original = workout([set(load: 100, reps: 5)])

        #expect(original.annotatingSet(at: 0, 9, with: "x") == original)
    }

    @Test("moving a set to an exercise that already has an entry appends it there")
    func movingToExistingEntry() {
        let original = Workout(
            entries: [
                Entry(exercise: bench, sets: [set(load: 100, reps: 5), set(load: 100, reps: 5)]),
                Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
            ],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        let edited = original.movingSet(at: 0, 1, toExercise: squat)

        #expect(edited.entries.map(\.exercise) == [bench, squat])
        #expect(edited.entries[0].sets.count == 1)
        #expect(edited.entries[1].sets.map(\.loadKilograms) == [140, 100]) // moved set appended at the end
    }

    @Test("moving a set to an unknown exercise creates a new entry for it")
    func movingToNewEntry() {
        let curl = Exercise(name: "Curl", aliases: ["curl"])
        let original = Workout(
            entries: [Entry(exercise: bench, sets: [set(load: 100, reps: 5), set(load: 100, reps: 5)])],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        let edited = original.movingSet(at: 0, 0, toExercise: curl)

        #expect(edited.entries.map(\.exercise.name) == ["Bench", "Curl"])
        #expect(edited.entries[1].sets.count == 1)
    }

    @Test("moving the last set out of an entry drops the entry")
    func movingLastSetDropsSourceEntry() {
        let original = Workout(
            entries: [
                Entry(exercise: bench, sets: [set(load: 100, reps: 5)]),
                Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
            ],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        let edited = original.movingSet(at: 0, 0, toExercise: squat)

        #expect(edited.entries.map(\.exercise) == [squat])
        #expect(edited.entries[0].sets.count == 2)
    }

    @Test("moving from an entry that precedes an emptied source still finds the target")
    func movingResolvesTargetAfterSourceRemoval() {
        // Source entry (index 0) empties and is removed; the target (squat) shifts
        // from index 1 to index 0. The transform must still land the set on squat.
        let original = Workout(
            entries: [
                Entry(exercise: bench, sets: [set(load: 100, reps: 5)]),
                Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
            ],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        let edited = original.movingSet(at: 0, 0, toExercise: squat)

        #expect(edited.entries.count == 1)
        #expect(edited.entries[0].exercise == squat)
        #expect(edited.entries[0].sets.map(\.loadKilograms) == [140, 100])
    }

    @Test("moving a set matches the target entry by whole value, not just display name (1d)")
    func movingMatchesTargetByValue() {
        let squatNoAlias = Exercise(name: "Squat", aliases: [])
        let original = Workout(
            entries: [
                Entry(exercise: bench, sets: [set(load: 100, reps: 5), set(load: 100, reps: 5)]),
                Entry(exercise: squat, sets: [set(load: 140, reps: 3)]), // squat has aliases: ["squat"]
            ],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        // squatNoAlias shares the display name but differs in aliases, so it is a
        // distinct Exercise: the moved set lands in its own new entry rather than
        // silently merging into the existing "Squat" entry.
        let edited = original.movingSet(at: 0, 0, toExercise: squatNoAlias)

        #expect(edited.entries.map(\.exercise) == [bench, squat, squatNoAlias])
        #expect(edited.entries.last?.sets.count == 1)

        // Moving to the exact same Exercise value still merges.
        let merged = original.movingSet(at: 0, 0, toExercise: squat)
        #expect(merged.entries.count == 2)
        #expect(merged.entries[1].sets.count == 2)
    }

    @Test("a moved set keeps its axes, note, timestamp, and superset run id")
    func movingCarriesEverySetField() {
        let grouped = LoggedSet(
            loadType: .added, effort: .reps, role: .warmup, grouping: .superset,
            loadKilograms: 62.5, reps: 9, supersetRunID: 3,
            loggedAt: Date(timeIntervalSince1970: 111), note: "paused"
        )
        let original = Workout(
            entries: [
                Entry(exercise: bench, sets: [set(load: 100, reps: 5), grouped]),
                Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
            ],
            startedAt: Date(timeIntervalSince1970: 0)
        )

        let edited = original.movingSet(at: 0, 1, toExercise: squat)

        #expect(edited.entries[1].sets.last == grouped)
    }

    @Test("moving a set at an out-of-range index changes nothing")
    func movingOutOfRangeIsNoOp() {
        let original = workout([set(load: 100, reps: 5)])
        #expect(original.movingSet(at: 0, 9, toExercise: squat) == original)
        #expect(original.movingSet(at: 4, 0, toExercise: squat) == original)
    }

    @Test("moving a set to the exercise it is already under changes nothing")
    func movingToSameExerciseIsNoOp() {
        let original = workout([set(load: 100, reps: 5), set(load: 100, reps: 5)])
        #expect(original.movingSet(at: 0, 0, toExercise: bench) == original)
    }

    // MARK: - Cluster 3: join a set into a superset run (story 26, second half)

    @Test("joining a set into a run stamps the run id and marks it a superset")
    func joiningIntoRun() {
        let inRun = LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .superset,
            loadKilograms: 40, reps: 12, supersetRunID: 2,
            loggedAt: Date(timeIntervalSince1970: 0)
        )
        let loose = set(load: 100, reps: 5) // .straight, no run
        let original = workout([inRun, loose])

        let edited = original.joiningSet(at: 0, 1, intoRun: 2)

        #expect(edited.entries[0].sets[1].supersetRunID == 2)
        #expect(edited.entries[0].sets[1].grouping == .superset)
        #expect(edited.entries[0].sets[0] == inRun) // the other set untouched
    }

    @Test("joining a set at an out-of-range index changes nothing")
    func joiningOutOfRangeIsNoOp() {
        let original = workout([set(load: 100, reps: 5)])
        #expect(original.joiningSet(at: 0, 5, intoRun: 1) == original)
        #expect(original.joiningSet(at: 9, 0, intoRun: 1) == original)
    }

    // MARK: - Cluster 3: correct a recorded set's effort measure / load type

    @Test("switching a set's effort measure clears the values that no longer apply")
    func changingEffortMeasure() {
        // A reps set being corrected to a timed hold.
        let repsSet = LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 60, reps: 10, loggedAt: Date(timeIntervalSince1970: 0)
        )
        let edited = workout([repsSet]).changingSet(at: 0, 0, effort: .duration)

        #expect(edited.entries[0].sets[0].effort == .duration)
        #expect(edited.entries[0].sets[0].reps == nil)           // no longer meaningful
        #expect(edited.entries[0].sets[0].distanceMeters == nil)
        #expect(edited.entries[0].sets[0].loadKilograms == 60)   // load axis is orthogonal
    }

    @Test("switching a set's load type to bodyweight drops the load number")
    func changingLoadTypeToBodyweight() {
        let edited = workout([set(load: 100, reps: 5)]).changingSet(at: 0, 0, loadType: .bodyweight)

        #expect(edited.entries[0].sets[0].loadType == .bodyweight)
        #expect(edited.entries[0].sets[0].loadKilograms == nil)
        #expect(edited.entries[0].sets[0].reps == 5)             // effort axis untouched
    }

    @Test("switching load type to assisted keeps the load number (it is the assistance)")
    func changingLoadTypeToAssistedKeepsLoad() {
        let edited = workout([set(load: 20, reps: 8)]).changingSet(at: 0, 0, loadType: .assisted)

        #expect(edited.entries[0].sets[0].loadType == .assisted)
        #expect(edited.entries[0].sets[0].loadKilograms == 20)
    }

    @Test("changing a set at an out-of-range index changes nothing")
    func changingOutOfRangeIsNoOp() {
        let original = workout([set(load: 100, reps: 5)])
        #expect(original.changingSet(at: 0, 7, effort: .distance) == original)
        #expect(original.changingSet(at: 5, 0, loadType: .assisted) == original)
    }
}
