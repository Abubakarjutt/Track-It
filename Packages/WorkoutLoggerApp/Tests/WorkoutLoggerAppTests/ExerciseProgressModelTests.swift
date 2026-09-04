import Foundation
import Testing
import SwiftData
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("ExerciseProgressModel")
@MainActor
struct ExerciseProgressModelTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])
    private let squat = Exercise(name: "Squat", aliases: ["squat"])

    private func inMemoryStore() throws -> SwiftDataWorkoutStore {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataWorkoutStore(context: ModelContext(container))
    }

    private func working(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }

    private func workout(_ started: TimeInterval, _ exercise: Exercise, _ sets: [LoggedSet]) -> Workout {
        Workout(entries: [Entry(exercise: exercise, sets: sets)],
                startedAt: Date(timeIntervalSince1970: started),
                endedAt: Date(timeIntervalSince1970: started + 60))
    }

    @Test("the model folds only the completed workouts that used the exercise, oldest first")
    func foldsMatchingCompletedWorkouts() throws {
        let store = try inMemoryStore()
        store.save(workout(1_000, bench, [working(100, 5)]))
        store.save(workout(2_000, squat, [working(140, 5)]))   // different exercise
        store.save(workout(3_000, bench, [working(105, 5)]))

        let model = ExerciseProgressModel(exercise: bench, store: store, unit: .kilograms)

        #expect(model.projection.volumeSeries.map(\.value) == [500, 525])
        #expect(model.projection.comparison?.volumeDelta == 25)
    }

    @Test("an unavailable store yields an empty projection, not a crash")
    func unavailableIsEmpty() throws {
        let store = try inMemoryStore()
        store.save(workout(1_000, bench, [working(100, 5)]))

        let model = ExerciseProgressModel(exercise: bench, store: store, unit: .kilograms,
                                          historyUnavailable: true)

        #expect(model.projection.volumeSeries.isEmpty)
        #expect(model.projection.comparison == nil)
    }
}
