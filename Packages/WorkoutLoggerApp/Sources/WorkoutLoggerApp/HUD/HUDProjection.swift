import Foundation
import WorkoutLoggerCore

/// The exact set of glanceable fields the live-workout HUD renders, derived from
/// a `WorkoutSessionModel` snapshot. All fallback and formatting logic lives here
/// so the SwiftUI view is a dumb renderer — and so every rule is `swift test`ed.
public struct HUDProjection: Equatable, Sendable {
    public var exerciseName: String
    public var lastSetLine: String?
    public var restLine: String?
    public var restTargetReached: Bool
    public var isListening: Bool
    public var currentEntrySetLines: [String]
    public var tapSelectCandidates: [Exercise]?

    public init(
        exerciseName: String,
        lastSetLine: String?,
        restLine: String?,
        restTargetReached: Bool,
        isListening: Bool,
        currentEntrySetLines: [String],
        tapSelectCandidates: [Exercise]?
    ) {
        self.exerciseName = exerciseName
        self.lastSetLine = lastSetLine
        self.restLine = restLine
        self.restTargetReached = restTargetReached
        self.isListening = isListening
        self.currentEntrySetLines = currentEntrySetLines
        self.tapSelectCandidates = tapSelectCandidates
    }

    @MainActor
    public init(from model: WorkoutSessionModel) {
        let entry = model.workout?.entries.last
        let unit = model.displayUnit
        exerciseName = entry?.exercise.name ?? "No exercise yet"
        lastSetLine = entry?.sets.last.map { formattedSetLine($0, unit: unit) }
        restLine = model.restStartedAt == nil ? nil : HUDProjection.clock(model.restElapsed)
        restTargetReached = model.isRestTargetReached
        isListening = model.isListening
        currentEntrySetLines = (entry?.sets ?? []).map { formattedSetLine($0, unit: unit) }
        tapSelectCandidates = model.tapSelectCandidates
    }

    /// `m:ss` count-up. Negative / sub-second clamps to `0:00`.
    static func clock(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
