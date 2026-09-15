import Foundation

/// The compact, `ActivityKit`-free snapshot of live-workout state the Live
/// Activity needs (cluster 7c). Lives in `WorkoutLoggerApp`, not `App/`, so
/// the "what does the Activity show" derivation is one `swift test`ed place
/// rather than logic embedded in the widget-extension controller reaching
/// into `WorkoutSessionModel`'s many properties (Feature Envy) — this
/// mirrors `HUDProjection`'s role for the on-screen HUD.
public struct WorkoutActivityState: Equatable, Sendable {
    public var exerciseName: String
    public var workingSetCount: Int
    public var isResting: Bool
    public var restDeadline: Date?
    public var isListening: Bool

    public init(
        exerciseName: String, workingSetCount: Int, isResting: Bool,
        restDeadline: Date?, isListening: Bool
    ) {
        self.exerciseName = exerciseName
        self.workingSetCount = workingSetCount
        self.isResting = isResting
        self.restDeadline = restDeadline
        self.isListening = isListening
    }

    /// `nil` when no workout is active — the controller reads that as "end
    /// the Activity".
    @MainActor
    public init?(from model: WorkoutSessionModel) {
        guard model.hasActiveWorkout else { return nil }
        let entry = model.activeEntry()
        exerciseName = entry?.exercise.name ?? "Workout in progress"
        workingSetCount = entry?.sets.filter { $0.role == .working }.count ?? 0
        isResting = model.restStartedAt != nil
        restDeadline = model.restDeadline
        isListening = model.isListening
    }
}
