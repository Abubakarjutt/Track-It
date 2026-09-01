import Foundation
import WorkoutLoggerCore

/// Everything the completed-workout detail screen renders, derived from one
/// `Workout` plus the history that precedes it. Pure and `swift test`-covered so
/// the SwiftUI view stays a dumb renderer. Warm-up sets are shown but excluded
/// from every total and from personal-record consideration (CONTEXT.md "Role").
public struct WorkoutSummaryProjection: Equatable, Sendable {
    public struct SetRow: Equatable, Sendable {
        public var line: String
        public var isPersonalRecord: Bool
        public init(line: String, isPersonalRecord: Bool) {
            self.line = line
            self.isPersonalRecord = isPersonalRecord
        }
    }

    public struct EntryRow: Equatable, Sendable {
        public var exerciseName: String
        public var sets: [SetRow]
        public init(exerciseName: String, sets: [SetRow]) {
            self.exerciseName = exerciseName
            self.sets = sets
        }
    }

    public var entries: [EntryRow]
    public var totalVolumeText: String
    public var totalWorkingReps: Int
    public var durationText: String
    public var note: String?

    public init(entries: [EntryRow], totalVolumeText: String, totalWorkingReps: Int,
                durationText: String, note: String?) {
        self.entries = entries
        self.totalVolumeText = totalVolumeText
        self.totalWorkingReps = totalWorkingReps
        self.durationText = durationText
        self.note = note
    }

    public init(workout: Workout, priorHistory: [Workout], unit: MassUnit) {
        entries = workout.entries.map { entry in
            let priorBest = exerciseProgress(for: entry.exercise, across: priorHistory)
                .bestEstimatedOneRepMaxKilograms
            let recordSetIndex = Self.personalRecordSetIndex(in: entry.sets, beating: priorBest)
            let rows = entry.sets.enumerated().map { index, set in
                SetRow(line: formattedSetLine(set, unit: unit), isPersonalRecord: index == recordSetIndex)
            }
            return EntryRow(exerciseName: entry.exercise.name, sets: rows)
        }

        let working = workout.entries.flatMap(\.sets).filter { $0.role == .working }
        let volume = working.reduce(0.0) { running, set in
            guard let load = set.loadKilograms, let reps = set.reps else { return running }
            return running + load * Double(reps)
        }
        totalVolumeText = loadString(volume, unit: unit)
        totalWorkingReps = working.reduce(0) { $0 + ($1.reps ?? 0) }

        let end = workout.endedAt ?? workout.lastActivityAt
        let minutes = Int(end.timeIntervalSince(workout.startedAt) / 60)
        durationText = "\(minutes) min"

        note = workout.note
    }

    /// The index of the working set with the greatest Epley estimate, but only
    /// when `priorBest` exists and that estimate strictly clears it. `nil`
    /// otherwise — no prior history for the exercise means nothing to beat.
    private static func personalRecordSetIndex(in sets: [LoggedSet], beating priorBest: Double?) -> Int? {
        guard let priorBest else { return nil }
        var bestIndex: Int?
        var bestEstimate = priorBest
        for (index, set) in sets.enumerated() {
            guard set.role == .working, let load = set.loadKilograms, let reps = set.reps else { continue }
            let estimate = estimatedOneRepMax(loadKilograms: load, reps: reps)
            if estimate > bestEstimate {
                bestEstimate = estimate
                bestIndex = index
            }
        }
        return bestIndex
    }
}
