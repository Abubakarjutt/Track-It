import Foundation
import ActivityKit
import Observation
import WorkoutLoggerApp

/// Starts, updates, and ends the workout Live Activity (cluster 7c) — a
/// second observer of `WorkoutSessionModel`, alongside `HUDView` and
/// `RemoteCommandPushToTalk` (7b). Local-only updates (OPEN QUESTION 3): no
/// push, no server — `Activity.update(...)` runs whenever this process is
/// alive to observe a state change.
///
/// `@MainActor` because `WorkoutSessionModel` and `ActivityKit`'s
/// `Activity` type are both main-actor-bound in practice.
@MainActor
final class LiveActivityController {
    private let session: WorkoutSessionModel
    private var activity: Activity<WorkoutActivityAttributes>?

    init(session: WorkoutSessionModel) {
        self.session = session
        observe()
    }

    /// Re-arms itself after every fire, same self-re-arming
    /// `withObservationTracking` pattern as `RemoteCommandPushToTalk` (7b).
    private func observe() {
        withObservationTracking {
            _ = session.hasActiveWorkout
            _ = session.workout
            _ = session.restStartedAt
            _ = session.isListening
        } onChange: { [weak self] in
            Task { @MainActor in
                await self?.sync()
                self?.observe()
            }
        }
        Task { @MainActor in await sync() }
    }

    /// `async`, called directly with `await` rather than wrapped in a nested
    /// `Task`. `Activity.update`/`.end` are themselves `nonisolated` async
    /// methods, so calling either from this `@MainActor` method "sends" the
    /// receiver off the actor regardless of a `Task` wrapper — and since
    /// `Activity<WorkoutActivityAttributes>` isn't `Sendable` in this SDK,
    /// the compiler can't prove `self.activity` stays unaliased for the
    /// call's duration ("sending 'activity' risks causing data races").
    /// `nonisolated(unsafe)` on each local copy, immediately before its one
    /// `await` call, is the documented escape hatch: ActivityKit's own
    /// `Activity` methods are safe to call from any isolation domain
    /// (that's the whole point of `update`/`end` being `nonisolated`) — the
    /// SDK just predates `Sendable` annotations expressing that. (A shared
    /// helper that took the closure as a parameter was tried and rejected —
    /// the `nonisolated(unsafe)` marking on a local doesn't survive being
    /// passed through a closure boundary, so the same error resurfaces one
    /// level down; the two-line repetition below is the actual fix.)
    private func sync() async {
        guard let state = WorkoutActivityState(from: session) else {
            if let activity {
                nonisolated(unsafe) let activityToEnd = activity
                await activityToEnd.end(nil, dismissalPolicy: .immediate)
            }
            activity = nil
            return
        }
        let content = WorkoutActivityAttributes.ContentState(
            exerciseName: state.exerciseName,
            workingSetCount: state.workingSetCount,
            isResting: state.isResting,
            restDeadline: state.restDeadline,
            isListening: state.isListening
        )
        if let activity {
            nonisolated(unsafe) let activityToUpdate = activity
            await activityToUpdate.update(ActivityContent(state: content, staleDate: nil))
        } else {
            activity = try? Activity.request(
                attributes: WorkoutActivityAttributes(),
                content: ActivityContent(state: content, staleDate: nil)
            )
        }
    }
}
