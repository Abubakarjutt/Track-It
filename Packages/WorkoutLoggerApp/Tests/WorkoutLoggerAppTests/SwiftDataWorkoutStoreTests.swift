import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SwiftDataWorkoutStore")
@MainActor
struct SwiftDataWorkoutStoreTests {

    private func makeStoreAndContext() throws -> (SwiftDataWorkoutStore, ModelContext) {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (SwiftDataWorkoutStore(context: context), context)
    }

    private func makeStore() throws -> SwiftDataWorkoutStore {
        try makeStoreAndContext().0
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

    @Test("a workout round-trips through the versioned payload envelope, intact")
    func roundTripThroughVersionedEnvelope() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 1_000, reps: 5))

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.entries.first?.sets.first?.reps == 5)
        #expect(history.first?.entries.first?.sets.first?.loadKilograms == 100)
        #expect(store.decodeFailureCount == 0)
    }

    @Test("an undecodable payload is counted, not silently dropped, and good records survive")
    func undecodablePayloadIsCountedNotDropped() throws {
        let (store, context) = try makeStoreAndContext()
        store.save(workout(startedAt: 1_000, reps: 5))
        context.insert(WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: nil,
            payload: Data("not json".utf8)
        ))
        try context.save()

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.entries.first?.sets.first?.reps == 5)
        #expect(store.decodeFailureCount == 1)
    }

    @Test("a legacy bare (un-enveloped) payload still decodes")
    func legacyBarePayloadStillDecodes() throws {
        let (store, context) = try makeStoreAndContext()
        let bare = workout(startedAt: 3_000, reps: 7)
        context.insert(WorkoutRecord(
            startedAt: bare.startedAt,
            endedAt: bare.endedAt,
            payload: try JSONEncoder().encode(bare)
        ))
        try context.save()

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.entries.first?.sets.first?.reps == 7)
        #expect(store.decodeFailureCount == 0)
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

    @Test("deleteAllWorkouts empties history and leaves colocated exercise records")
    func deleteAllWorkouts() throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self, ExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = SwiftDataWorkoutStore(context: context)
        store.save(workout(startedAt: 1_000, reps: 5, endedAt: 1_500))
        store.save(workout(startedAt: 2_000, reps: 3, endedAt: 2_500))
        context.insert(ExerciseRecord(name: "Bench Press", aliases: ["bench"]))
        try context.save()

        store.deleteAllWorkouts()

        #expect(store.history().isEmpty)
        let exercises = try context.fetch(FetchDescriptor<ExerciseRecord>())
        #expect(exercises.count == 1)
    }
}
