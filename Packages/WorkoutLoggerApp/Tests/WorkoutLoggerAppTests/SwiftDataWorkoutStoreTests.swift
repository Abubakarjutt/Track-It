import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SwiftDataWorkoutStore")
@MainActor
struct SwiftDataWorkoutStoreTests {

    private func makeStore() throws -> SwiftDataWorkoutStore {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataWorkoutStore(context: ModelContext(container))
    }

    private func workout(startedAt: TimeInterval, reps: Int, endedAt: TimeInterval? = nil) -> Workout {
        let set = LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 100, reps: reps, durationSeconds: nil, distanceMeters: nil,
            supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: startedAt + 10), note: nil
        )
        return Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [set])],
            startedAt: Date(timeIntervalSince1970: startedAt),
            endedAt: endedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    @Test("save then history returns the workout")
    func saveAndRead() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 1_000, reps: 5))

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.entries.first?.sets.first?.reps == 5)
    }

    @Test("saving the same session twice updates in place")
    func upsert() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 1_000, reps: 5))
        store.save(workout(startedAt: 1_000, reps: 8)) // same startedAt, grown

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.entries.first?.sets.first?.reps == 8)
    }

    @Test("two sessions are two records, ordered by startedAt")
    func twoSessions() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 2_000, reps: 3))
        store.save(workout(startedAt: 1_000, reps: 5))

        let history = store.history()
        #expect(history.map(\.startedAt) == [
            Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 2_000),
        ])
    }

    @Test("openWorkout is the un-ended one, nil once every workout is ended")
    func openWorkout() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 1_000, reps: 5, endedAt: 1_500))
        store.save(workout(startedAt: 2_000, reps: 5)) // open
        #expect(store.openWorkout()?.startedAt == Date(timeIntervalSince1970: 2_000))

        store.save(workout(startedAt: 2_000, reps: 5, endedAt: 2_500)) // now ended
        #expect(store.openWorkout() == nil)
        #expect(store.history().count == 2)
    }
}
