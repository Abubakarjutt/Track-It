import Foundation
import Testing
import SwiftData
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutHistoryModel")
@MainActor
struct WorkoutHistoryModelTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])

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

    private func workout(started: TimeInterval, ended: TimeInterval?, sets: [LoggedSet]) -> Workout {
        Workout(entries: [Entry(exercise: bench, sets: sets)],
                startedAt: Date(timeIntervalSince1970: started),
                endedAt: ended.map { Date(timeIntervalSince1970: $0) })
    }

    @Test("rows are the completed workouts, newest first; an open workout is excluded")
    func loadsCompletedNewestFirst() throws {
        let store = try inMemoryStore()
        store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
        store.save(workout(started: 3_000, ended: 3_500, sets: [working(110, 5)]))
        store.save(workout(started: 5_000, ended: nil, sets: [working(120, 5)])) // open

        let model = WorkoutHistoryModel(store: store)

        #expect(model.rows.map(\.startedAt) == [
            Date(timeIntervalSince1970: 3_000), Date(timeIntervalSince1970: 1_000),
        ])
        #expect(model.isUnavailable == false)
    }

    @Test("applyEdit with replacingSet persists the change and re-selects the workout")
    func editPersistsAndReSelects() throws {
        let store = try inMemoryStore()
        store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5), working(100, 5)]))
        let model = WorkoutHistoryModel(store: store)
        model.open(model.rows[0])

        model.applyEdit { $0.replacingSet(at: 0, 1, with: working(90, 8)) }

        #expect(model.saveError == nil)
        #expect(model.rows.count == 1)                                  // no duplicate
        #expect(model.selected?.startedAt == Date(timeIntervalSince1970: 1_000))
        #expect(model.selected?.entries[0].sets.map(\.reps) == [5, 8])
        #expect(store.history().first?.entries[0].sets.map(\.reps) == [5, 8]) // actually stored
    }

    @Test("applyEdit with movingSet relocates the set in the stored workout")
    func editMovesSet() throws {
        let squat = Exercise(name: "Squat", aliases: ["squat"])
        let store = try inMemoryStore()
        let w = Workout(
            entries: [
                Entry(exercise: bench, sets: [working(100, 5), working(100, 5)]),
                Entry(exercise: squat, sets: [working(140, 5)]),
            ],
            startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_500)
        )
        store.save(w)
        let model = WorkoutHistoryModel(store: store)
        model.open(model.rows[0])

        model.applyEdit { $0.movingSet(at: 0, 0, toExercise: squat) }

        #expect(model.selected?.entries.map { $0.exercise.name } == ["Bench", "Squat"])
        #expect(model.selected?.entries[1].sets.count == 2)
    }

    @Test("applyEdit with removingSet drops the set, and the entry if it empties")
    func editRemovesSet() throws {
        let store = try inMemoryStore()
        store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
        let model = WorkoutHistoryModel(store: store)
        model.open(model.rows[0])

        model.applyEdit { $0.removingSet(at: 0, 0) }

        #expect(model.selected?.entries.isEmpty == true)
    }

    @Test("applyEdit with annotated persists the workout note")
    func editAnnotates() throws {
        let store = try inMemoryStore()
        store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
        let model = WorkoutHistoryModel(store: store)
        model.open(model.rows[0])

        model.applyEdit { $0.annotated(with: "tough session") }

        #expect(model.selected?.note == "tough session")
        #expect(store.history().first?.note == "tough session")
    }

    @Test("a failed save leaves the open workout untouched, records the error, and does not reload")
    func saveFailureIsSurfaced() {
        let w = Workout(entries: [Entry(exercise: bench, sets: [working(100, 5)])],
                        startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_500))
        let store = FailingHistoryStore([w])
        let model = WorkoutHistoryModel(store: store)
        model.open(model.rows[0])
        let before = model.selected

        model.applyEdit { $0.annotated(with: "should not stick") }

        #expect(model.saveError != nil)
        #expect(model.selected == before)          // unchanged
    }

    @Test("an unavailable store yields no rows and the unavailable flag")
    func unavailable() throws {
        let store = try inMemoryStore()
        store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))

        let model = WorkoutHistoryModel(store: store, historyUnavailable: true)

        #expect(model.rows.isEmpty)
        #expect(model.isUnavailable)
    }

    @Test("deleteAllWorkoutData clears the rows and the store")
    func deleteAllWorkoutData() throws {
        let store = try inMemoryStore()
        store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
        store.save(workout(started: 3_000, ended: 3_500, sets: [working(110, 5)]))
        let model = WorkoutHistoryModel(store: store)
        model.open(model.rows[0])
        #expect(model.rows.count == 2)

        model.deleteAllWorkoutData()

        #expect(model.rows.isEmpty)
        #expect(model.selected == nil)
        #expect(store.history().isEmpty)
    }
}

private final class FailingHistoryStore: WorkoutHistoryStore {
    private var stored: [Workout]
    var lastSaveError: Error?
    struct Boom: Error {}

    init(_ stored: [Workout]) { self.stored = stored }
    func history() -> [Workout] { stored }
    func save(_ workout: Workout) { lastSaveError = Boom() } // never actually stores
    func deleteAllWorkouts() { stored = [] }
}
