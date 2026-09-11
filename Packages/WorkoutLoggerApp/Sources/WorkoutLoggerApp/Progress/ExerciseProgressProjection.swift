import Foundation
import WorkoutLoggerCore

/// Everything the per-exercise progress screen draws, derived from the core's
/// `ExerciseProgress`. Pure and `swift test`-covered. `ExerciseProgress.sessions`
/// carries no rep count or full set, so the top-set call-out and comparison are
/// load and estimated-1RM only — never a "load × reps" line.
public struct ExerciseProgressProjection: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var date: Date
        public var value: Double
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
          }
      }

    public struct Comparison: Equatable, Sendable {
        public var topSetLoadDelta: Double?
        public var volumeDelta: Double
        public var estimatedOneRepMaxDelta: Double?
          /// The change in this exercise's working-set count (its set volume) from
          /// the second-latest to the latest session. A plain `Int` count — never a
          /// load (CONTEXT.md "Set volume").
        public var setVolumeDelta: Int
        public init(topSetLoadDelta: Double?, volumeDelta: Double, estimatedOneRepMaxDelta: Double?,
                    setVolumeDelta: Int) {
            self.topSetLoadDelta = topSetLoadDelta
            self.volumeDelta = volumeDelta
            self.estimatedOneRepMaxDelta = estimatedOneRepMaxDelta
            self.setVolumeDelta = setVolumeDelta
          }
      }

    public var loadSeries: [Point]
    public var volumeSeries: [Point]
    public var estimatedOneRepMaxSeries: [Point]
      /// One point per session: that session's working-set count (its set volume,
      /// CONTEXT.md "Set volume"), oldest first. Distinct from `volumeSeries`
      /// (tonnage); a bodyweight or timed session still contributes a point here.
    public var setVolumeSeries: [Point]
    public var topSetText: String?
    public var comparison: Comparison?

    public init(loadSeries: [Point], volumeSeries: [Point], estimatedOneRepMaxSeries: [Point],
                setVolumeSeries: [Point], topSetText: String?, comparison: Comparison?) {
        self.loadSeries = loadSeries
        self.volumeSeries = volumeSeries
        self.estimatedOneRepMaxSeries = estimatedOneRepMaxSeries
        self.setVolumeSeries = setVolumeSeries
        self.topSetText = topSetText
        self.comparison = comparison
      }

    public init(progress: ExerciseProgress, unit: MassUnit) {
        let sessions = progress.sessions
        loadSeries = sessions.compactMap { s in
            s.topSetLoadKilograms.map { Point(date: s.date, value: displayLoad($0, unit: unit)) }
          }
        volumeSeries = sessions.map { Point(date: $0.date, value: displayLoad($0.volumeKilograms, unit: unit)) }
        estimatedOneRepMaxSeries = sessions.compactMap { s in
            s.bestEstimatedOneRepMaxKilograms.map { Point(date: s.date, value: displayLoad($0, unit: unit)) }
          }
        setVolumeSeries = sessions.map { Point(date: $0.date, value: Double($0.workingSetCount)) }
        if let last = sessions.last, let top = last.topSetLoadKilograms {
            if let e1rm = last.bestEstimatedOneRepMaxKilograms {
                topSetText = "\(loadString(top, unit: unit)) · est. 1RM \(loadString(e1rm, unit: unit))"
              } else {
                topSetText = loadString(top, unit: unit)
              }
          } else {
            topSetText = nil
          }

        if sessions.count >= 2 {
            let last = sessions[sessions.count - 1]
            let prev = sessions[sessions.count - 2]
            comparison = Comparison(
                topSetLoadDelta: delta(last.topSetLoadKilograms, prev.topSetLoadKilograms, unit: unit),
                volumeDelta: displayLoad(last.volumeKilograms, unit: unit)
                      - displayLoad(prev.volumeKilograms, unit: unit),
                estimatedOneRepMaxDelta: delta(last.bestEstimatedOneRepMaxKilograms,
                                              prev.bestEstimatedOneRepMaxKilograms, unit: unit),
                setVolumeDelta: last.workingSetCount - prev.workingSetCount
              )
          } else {
            comparison = nil
          }
      }

    private func delta(_ a: Double?, _ b: Double?, unit: MassUnit) -> Double? {
        guard let a, let b else { return nil }
        return displayLoad(a, unit: unit) - displayLoad(b, unit: unit)
      }
}
