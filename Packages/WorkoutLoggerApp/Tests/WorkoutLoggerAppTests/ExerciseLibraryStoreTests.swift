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

    // Naming validation (trimmed non-empty, case-insensitively unique) lives
    // at the SettingsModel seam now — see SettingsModelTests. This store is
    // plain persistence and is tested as such.

    @Test("add / update / delete round-trip; all() is alphabetical")
    func crudRoundTrip() throws {
        let (store, _) = try makeStore()
        store.add(Exercise(name: "Row", aliases: ["barbell row"]))
        store.add(Exercise(name: "Curl"))
        store.update(named: "Row", to: Exercise(name: "Pendlay Row", aliases: ["pendlay"]))
        store.delete(named: "Curl")

        let all = store.all()
        #expect(all.map(\.name) == ["Pendlay Row"])
        #expect(all.first?.aliases == ["pendlay"])
    }

    @Test("update by original name is case-insensitive and re-aliases in place")
    func updateMatchesCaseInsensitively() throws {
        let (store, _) = try makeStore()
        store.add(Exercise(name: "Squat"))

        store.update(named: "squat", to: Exercise(name: "Squat", aliases: ["back squat"]))

        #expect(store.all().first(where: { $0.name == "Squat" })?.aliases == ["back squat"])
    }

    @Test("deleting an exercise leaves stored workouts intact")
    func deleteDoesNotTouchWorkouts() throws {
        let (store, context) = try makeStore()
        store.add(Exercise(name: "Bench Press"))
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
