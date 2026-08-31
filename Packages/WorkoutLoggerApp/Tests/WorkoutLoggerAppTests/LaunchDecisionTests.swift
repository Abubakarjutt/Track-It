import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("LaunchDecision")
struct LaunchDecisionTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func openWorkout(lastSetAt t: TimeInterval) -> Workout {
        Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: t)),
            ])],
            startedAt: Date(timeIntervalSince1970: t - 100)
        )
    }

    @Test("no open workout is a fresh launch")
    func noneIsFresh() {
        #expect(launchDecision(openWorkout: nil, now: now) == .fresh)
    }

    @Test("an already-ended workout is a fresh launch")
    func endedIsFresh() {
        var w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 60)
        w.endedAt = Date(timeIntervalSince1970: now.timeIntervalSince1970 - 30)
        #expect(launchDecision(openWorkout: w, now: now) == .fresh)
    }

    @Test("a recently active open workout resumes silently")
    func recentResumes() {
        let w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 10 * 60) // 10 min ago
        #expect(launchDecision(openWorkout: w, now: now) == .resume(w))
    }

    @Test("an open workout stale past the threshold prompts")
    func stalePrompts() {
        let w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 8 * 60 * 60) // 8 h ago
        #expect(launchDecision(openWorkout: w, now: now) == .promptStale(w))
    }

    @Test("exactly at the threshold is not yet stale")
    func boundaryResumes() {
        let w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 6 * 60 * 60) // == staleAfter
        #expect(launchDecision(openWorkout: w, now: now) == .resume(w))
    }

    @Test("closeAbandonedWorkout closes at last-activity time, keeps the record and its sets")
    func closeAtLastActivity() throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let lastSet = Date(timeIntervalSince1970: 500)
        let w = openWorkout(lastSetAt: lastSet.timeIntervalSince1970)
        store.save(w) // it is on disk, open

        closeAbandonedWorkout(w, in: store)

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.endedAt == lastSet)          // not `now`
        #expect(history.first?.entries.first?.sets.count == 1)
        #expect(store.openWorkout() == nil)
    }
}
