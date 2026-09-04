import Foundation
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutSummaryProjection")
struct WorkoutSummaryProjectionTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])
    private let squat = Exercise(name: "Squat", aliases: ["squat"])

    private func working(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }
    private func warmup(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .warmup, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }

    @Test("entry rows carry formatted set lines; totals cover working sets only")
    func rowsAndTotals() {
        let workout = Workout(
            entries: [Entry(exercise: bench, sets: [warmup(60, 10), working(100, 5), working(100, 5)])],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 48 * 60)
        )

        let p = WorkoutSummaryProjection(workout: workout, priorHistory: [], unit: .kilograms)

        #expect(p.entries.count == 1)
        #expect(p.entries[0].exerciseName == "Bench")
        #expect(p.entries[0].sets.map(\.line) == ["warm-up 60 kg × 10", "100 kg × 5", "100 kg × 5"])
        #expect(p.totalWorkingReps == 10)          // 5 + 5; the warm-up's 10 do not count
        #expect(p.totalVolumeText == "1000 kg")    // 100*5 + 100*5
        #expect(p.durationText == "48 min")
    }

    @Test("a working set that beats prior history's best estimated 1RM is badged")
    func personalRecordBadged() {
        let prior = [Workout(
            entries: [Entry(exercise: bench, sets: [working(100, 5)])],   // e1RM 116.67
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
        )]
        let today = Workout(
            entries: [Entry(exercise: bench, sets: [working(100, 5), working(120, 5)])], // 116.67, 140
            startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_060)
        )

        let p = WorkoutSummaryProjection(workout: today, priorHistory: prior, unit: .kilograms)

        #expect(p.entries[0].sets.map(\.isPersonalRecord) == [false, true])
    }

    @Test("the first working set ever recorded for an exercise is not badged")
    func firstEverSetNotBadged() {
        let today = Workout(
            entries: [Entry(exercise: bench, sets: [working(140, 5)])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
        )

        let p = WorkoutSummaryProjection(workout: today, priorHistory: [], unit: .kilograms)

        #expect(p.entries[0].sets.map(\.isPersonalRecord) == [false])
    }

    @Test("a set that only ties the prior best is not badged")
    func tieNotBadged() {
        let prior = [Workout(
            entries: [Entry(exercise: bench, sets: [working(100, 5)])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
        )]
        let today = Workout(
            entries: [Entry(exercise: bench, sets: [working(100, 5)])],  // identical e1RM
            startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_060)
        )

        let p = WorkoutSummaryProjection(workout: today, priorHistory: prior, unit: .kilograms)

        #expect(p.entries[0].sets.allSatisfy { !$0.isPersonalRecord })
    }

    @Test("a warmup that would out-estimate prior history is never badged")
    func warmupNeverBadged() {
        let prior = [Workout(
            entries: [Entry(exercise: bench, sets: [working(100, 5)])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
        )]
        let today = Workout(
            entries: [Entry(exercise: bench, sets: [warmup(200, 5), working(100, 5)])],
            startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_060)
        )

        let p = WorkoutSummaryProjection(workout: today, priorHistory: prior, unit: .kilograms)

        #expect(p.entries[0].sets.map(\.isPersonalRecord) == [false, false])
    }

    @Test("the workout note is surfaced, and nil when absent")
    func noteSurfaced() {
        let base = Workout(entries: [Entry(exercise: bench, sets: [working(100, 5)])],
                           startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60))
        #expect(WorkoutSummaryProjection(workout: base, priorHistory: [], unit: .kilograms).note == nil)

        let annotated = base.annotated(with: "felt easy")
        #expect(WorkoutSummaryProjection(workout: annotated, priorHistory: [], unit: .kilograms).note == "felt easy")
    }

    @Test("a pounds projection formats the volume total in pounds")
    func poundsVolume() {
        let today = Workout(
            entries: [Entry(exercise: bench, sets: [working(100 * 0.45359237, 5)])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
        )
        let p = WorkoutSummaryProjection(workout: today, priorHistory: [], unit: .pounds)
        #expect(p.totalVolumeText == "500 lb")   // 100 lb × 5
    }
}
