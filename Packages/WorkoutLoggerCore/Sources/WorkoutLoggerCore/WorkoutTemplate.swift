// A reusable plan for a workout. Templates arm per-exercise rest targets; they
// never pre-create entries — announcing an exercise is still what puts it in the
// workout. See specs/v1-voice-logging.md (templates, Phase 4).

import Foundation

/// An ordered list of exercises to train, each optionally carrying a rest target
/// that overrides the engine default while that exercise is the one being worked.
public struct WorkoutTemplate: Equatable, Sendable {
    public var name: String
    public var items: [TemplateItem]

    public init(name: String, items: [TemplateItem]) {
        self.name = name
        self.items = items
    }
}

/// One line of a `WorkoutTemplate`.
public struct TemplateItem: Equatable, Sendable {
    public var exercise: Exercise
    /// How many working sets the plan calls for, or `nil` if unspecified. Carried
    /// for the HUD ("set 2 of 4") and the tap-to-log editor; the engine does not
    /// enforce or count against it.
    public var plannedSets: Int?
    /// The rest-period target for this exercise, or `nil` to use the engine default.
    public var restTargetSeconds: TimeInterval?

    public init(
        exercise: Exercise,
        plannedSets: Int? = nil,
        restTargetSeconds: TimeInterval? = nil
    ) {
        self.exercise = exercise
        self.plannedSets = plannedSets
        self.restTargetSeconds = restTargetSeconds
    }
}
