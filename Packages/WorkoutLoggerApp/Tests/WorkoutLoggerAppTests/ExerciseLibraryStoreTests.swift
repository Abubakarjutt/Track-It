import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SwiftDataExerciseLibraryStore")
@MainActor
struct ExerciseLibraryStoreTests {

    private func makeStore() throws -> (SwiftDataExerciseLibraryStore, ModelContext) {
        let container = try ModelContainer(
            for: ExerciseRecord.self, WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (SwiftDataExerciseLibraryStore(context: context), context)
    }

    @Test("seedIfEmpty inserts once, then is a no-op")
    func seedOnce() throws {
        let (store, _) = try makeStore()
        store.seedIfEmpty([Exercise(name: "Squat"), Exercise(name: "Bench")])
        store.seedIfEmpty([Exercise(name: "Deadlift")])

        #expect(store.all().map(\.name) == ["Bench", "Squat"])
    }

    @Test("add / update / delete round-trip; all() is alphabetical")
    func crudRoundTrip() throws {
        let (store, _) = try makeStore()
        try store.add(Exercise(name: "Row", aliases: ["barbell row"]))
        try store.add(Exercise(name: "Curl"))
        try store.update(named: "Row", to: Exercise(name: "Pendlay Row", aliases: ["pendlay"]))
        store.delete(named: "Curl")

        let all = store.all()
        #expect(all.map(\.name) == ["Pendlay Row"])
        #expect(all.first?.aliases == ["pendlay"])
    }

    @Test("empty and duplicate names are rejected")
    func validation() throws {
        let (store, _) = try makeStore()
        try store.add(Exercise(name: "Bench Press"))

        #expect(throws: ExerciseLibraryError.emptyName) {
            try store.add(Exercise(name: "   "))
        }
        #expect(throws: ExerciseLibraryError.duplicateName) {
            try store.add(Exercise(name: "bench press"))
        }
    }

    @Test("update lets a record keep its own name but rejects colliding with another")
    func updateDuplicateRules() throws {
        let (store, _) = try makeStore()
        try store.add(Exercise(name: "Bench Press"))
        try store.add(Exercise(name: "Squat"))

        try store.update(named: "Squat", to: Exercise(name: "Squat", aliases: ["back squat"]))
        #expect(store.all().first(where: { $0.name == "Squat" })?.aliases == ["back squat"])

        #expect(throws: ExerciseLibraryError.duplicateName) {
            try store.update(named: "Squat", to: Exercise(name: "Bench Press"))
        }
    }

    @Test("deleting an exercise leaves stored workouts intact")
    func deleteDoesNotTouchWorkouts() throws {
        let (store, context) = try makeStore()
        try store.add(Exercise(name: "Bench Press"))
        let workoutStore = SwiftDataWorkoutStore(context: context)
        let set = LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 100, reps: 5, durationSeconds: nil, distanceMeters: nil,
            supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: 10), note: nil
        )
        workoutStore.save(Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [set])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 100)
        ))

        store.delete(named: "Bench Press")

        #expect(store.all().isEmpty)
        #expect(workoutStore.history().count == 1)
    }

    @Test("defaultExerciseSeed is the six starters")
    func seedConstant() {
        #expect(defaultExerciseSeed.count == 6)
        #expect(defaultExerciseSeed.map(\.name).contains("Conventional Deadlift"))
    }
}
