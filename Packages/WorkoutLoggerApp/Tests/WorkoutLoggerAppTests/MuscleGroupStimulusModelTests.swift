import Foundation
import Testing
import SwiftData
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("MuscleGroupStimulusModel")
@MainActor
struct MuscleGroupStimulusModelTests {

    private let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
    private let squat = Exercise(name: "Barbell Back Squat", aliases: ["squat"])
    private let curl = Exercise(name: "Barbell Curl", aliases: ["curl"])      // not in the seed map

     // A fixed UTC calendar and a "now" inside one known Monday-start week
     // (2026-01-05 is a Monday; 2026-01-10 is its Friday) make the window
     // deterministic.
    private let utc = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
      }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
      }

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

      /// A finished workout that started at `started`, one entry of `exercise`.
    private func workout(_ started: Date, _ exercise: Exercise, _ sets: [LoggedSet]) -> Workout {
        Workout(entries: [Entry(exercise: exercise, sets: sets)],
                startedAt: started,
                endedAt: started.addingTimeInterval(60))
      }

      /// An unfinished (open) workout that started at `started`.
    private func openWorkout(_ started: Date, _ exercise: Exercise, _ sets: [LoggedSet]) -> Workout {
        Workout(entries: [Entry(exercise: exercise, sets: sets)],
                startedAt: started,
                endedAt: nil)
      }

      private func model(of store: SwiftDataWorkoutStore,
                         historyUnavailable: Bool = false) -> MuscleGroupStimulusModel {
        MuscleGroupStimulusModel(store: store,
                                 now: date(2026, 1, 10, hour: 9),
                                 calendar: utc,
                                 historyUnavailable: historyUnavailable)
      }

    @Test("folds the current week's per-group stimulus for the mapped starters")
    func foldsCurrentWeekPerGroup() throws {
        let store = try inMemoryStore()
        store.save(workout(date(2026, 1, 8), bench, [working(100, 5), working(110, 3)]))   // 2 → 3 groups
        store.save(workout(date(2026, 1, 9), squat, [working(140, 3)]))                    // 1 → 3 groups

        let model = model(of: store)

        #expect(model.currentWeek.perGroup[.chest] == 2)
        #expect(model.currentWeek.perGroup[.quads] == 1)
        #expect(model.currentWeek.perGroup[.back] == nil)     // no back work this week
        #expect(model.currentWeek.unclassified == 0)
        #expect(model.currentWeek.total == 9)                 // 2×3 + 1×3
        #expect(!model.isEmpty)
      }

    @Test("a workout from the previous week is outside the current window")
    func excludesOtherWeeks() throws {
        let store = try inMemoryStore()
        store.save(workout(date(2026, 1, 1), bench, [working(100, 5)]))     // week of 2025-12-29

        let model = model(of: store)

        #expect(model.isEmpty)
        #expect(model.currentWeek.total == 0)
      }

    @Test("an unmapped starter's sets land in the unclassified bucket")
    func unmappedGoesToUnclassified() throws {
        let store = try inMemoryStore()
        store.save(workout(date(2026, 1, 8), curl, [working(30, 10)]))      // not in the map

        let model = model(of: store)

        #expect(model.currentWeek.perGroup.isEmpty)
        #expect(model.currentWeek.unclassified == 1)
        #expect(!model.isEmpty)
      }

    @Test("unfinished workouts are excluded, like the other progress models")
    func excludesUnfinishedWorkouts() throws {
        let store = try inMemoryStore()
        store.save(openWorkout(date(2026, 1, 8), bench, [working(100, 5)])) // not ended

        let model = model(of: store)

        #expect(model.isEmpty)
      }

    @Test("an unavailable store yields an empty week, not a crash")
    func unavailableIsEmpty() throws {
        let store = try inMemoryStore()
        store.save(workout(date(2026, 1, 8), bench, [working(100, 5)]))

        let model = model(of: store, historyUnavailable: true)

        #expect(model.isEmpty)
        #expect(model.currentWeek.total == 0)
      }
}
