import Foundation
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("ExerciseProgressProjection")
struct ExerciseProgressProjectionTests {

    private func session(_ t: TimeInterval, volume: Double, reps: Int, top: Double?, e1rm: Double?) -> ExerciseSession {
        ExerciseSession(date: Date(timeIntervalSince1970: t), volumeKilograms: volume,
                        workingReps: reps, topSetLoadKilograms: top, bestEstimatedOneRepMaxKilograms: e1rm)
    }

    @Test("each session becomes one point per series, oldest first, and the top-set line is the latest session")
    func seriesAndTopSet() {
        let progress = ExerciseProgress(sessions: [
            session(1_000, volume: 1_000, reps: 10, top: 100, e1rm: 116.67),
            session(2_000, volume: 1_200, reps: 12, top: 110, e1rm: 128.33),
        ])

        let p = ExerciseProgressProjection(progress: progress, unit: .kilograms)

        #expect(p.loadSeries.map(\.value) == [100, 110])
        #expect(p.loadSeries.map(\.date) == [Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 2_000)])
        #expect(p.volumeSeries.map(\.value) == [1_000, 1_200])
        // every plotted value passes through displayLoad -> gymRound (1 decimal)
        #expect(p.estimatedOneRepMaxSeries.map(\.value) == [116.7, 128.3])
        // topSetLoad 110 -> "110 kg"; e1RM 128.33 -> "128.3 kg"
        #expect(p.topSetText == "110 kg · e1RM 128.3 kg")
    }

    @Test("the comparison is the last two sessions' deltas")
    func comparisonDeltas() {
        let progress = ExerciseProgress(sessions: [
            session(1_000, volume: 1_000, reps: 10, top: 100, e1rm: 110),
            session(2_000, volume: 1_150, reps: 11, top: 105, e1rm: 118),
        ])

        let c = ExerciseProgressProjection(progress: progress, unit: .kilograms).comparison

        #expect(c?.topSetLoadDelta == 5)
        #expect(c?.volumeDelta == 150)
        #expect(c?.estimatedOneRepMaxDelta == 8)
    }

    @Test("fewer than two sessions means no comparison")
    func noComparisonWithOneSession() {
        let progress = ExerciseProgress(sessions: [session(1_000, volume: 1_000, reps: 10, top: 100, e1rm: 110)])
        let p = ExerciseProgressProjection(progress: progress, unit: .kilograms)
        #expect(p.comparison == nil)
        #expect(p.loadSeries.count == 1)
    }

    @Test("an empty progress yields empty series and no comparison")
    func empty() {
        let p = ExerciseProgressProjection(progress: ExerciseProgress(sessions: []), unit: .kilograms)
        #expect(p.loadSeries.isEmpty)
        #expect(p.volumeSeries.isEmpty)
        #expect(p.estimatedOneRepMaxSeries.isEmpty)
        #expect(p.topSetText == nil)
        #expect(p.comparison == nil)
    }

    @Test("a bodyweight session contributes a volume point but no load or estimate point")
    func bodyweightSessionSparseSeries() {
        let progress = ExerciseProgress(sessions: [
            session(1_000, volume: 0, reps: 30, top: nil, e1rm: nil),
            session(2_000, volume: 0, reps: 33, top: nil, e1rm: nil),
        ])
        let p = ExerciseProgressProjection(progress: progress, unit: .kilograms)
        #expect(p.loadSeries.isEmpty)
        #expect(p.estimatedOneRepMaxSeries.isEmpty)
        #expect(p.volumeSeries.map(\.value) == [0, 0])
        #expect(p.topSetText == nil)                  // last session has no top set
        #expect(p.comparison?.topSetLoadDelta == nil)
        #expect(p.comparison?.volumeDelta == 0)
    }

    @Test("a pounds projection converts every plotted value")
    func poundsSeries() {
        let progress = ExerciseProgress(sessions: [
            session(1_000, volume: 100 * 0.45359237, reps: 1, top: 100 * 0.45359237, e1rm: 100 * 0.45359237),
        ])
        let p = ExerciseProgressProjection(progress: progress, unit: .pounds)
        #expect(p.loadSeries.map(\.value) == [100])
        #expect(p.volumeSeries.map(\.value) == [100])
        #expect(p.topSetText == "100 lb · e1RM 100 lb")
    }
}
