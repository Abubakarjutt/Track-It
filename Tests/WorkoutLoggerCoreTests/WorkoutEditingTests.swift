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
}
