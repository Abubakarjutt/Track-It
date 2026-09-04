import SwiftUI
import SwiftData
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Composition root. `@MainActor` so `init()` may build the `@MainActor`
/// `System*` adapters and the `@MainActor` `WorkoutSessionModel`.
@main
@MainActor
struct TrackitApp: App {
    @State private var model: WorkoutSessionModel
    private let historyModel: WorkoutHistoryModel
    private let store: SwiftDataWorkoutStore
    private let historyUnavailable: Bool

    init() {
        let storeURL = URL.applicationSupportDirectory.appending(path: "Trackit.store")
        let availability = provisionStore(onDiskURL: storeURL)
        historyUnavailable = availability.isDegraded

        let store = SwiftDataWorkoutStore(context: ModelContext(availability.container))
        self.store = store
        self.historyModel = WorkoutHistoryModel(
            store: store, historyUnavailable: availability.isDegraded
        )
        let library = ExerciseLibrary(TrackitApp.seedExercises)
        let history = availability.isDegraded ? [] : store.history()
        let knownBests = TrackitApp.knownBests(from: history)
        let engine = WorkoutEngine(store: store, library: library, knownBests: knownBests)

        let openWorkout = availability.isDegraded ? nil : store.openWorkout()
        var staleRecovery: StaleWorkoutRecovery?
        switch launchDecision(openWorkout: openWorkout, now: Date()) {
        case .fresh:
            break
        case .resume(let workout):
            engine.resume(workout)
        case .promptStale(let workout):
            staleRecovery = StaleWorkoutRecovery(
                workout: workout,
                onResume: { engine.resume(workout) },
                onDiscard: { closeAbandonedWorkout(workout, in: store) }
            )
        }

        _model = State(initialValue: WorkoutSessionModel(
            engine: engine,
            transcriptSource: SystemSpeechRecognizer(),
            readbackVoice: SystemReadbackVoice(),
            haptics: SystemHaptics(),
            library: library,
            knownBestExercises: Set(knownBests.keys),
            staleRecovery: staleRecovery,
            history: { store.history() }
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, historyModel: historyModel, store: store,
                     historyUnavailable: historyUnavailable)
        }
    }

    /// Best estimated 1RM per exercise name across completed history — the PR bar
    /// each exercise must clear this session.
    static func knownBests(from history: [Workout]) -> [String: Double] {
        var best: [String: Double] = [:]
        for workout in history {
            for entry in workout.entries {
                for set in entry.sets where set.role == .working {
                    guard let load = set.loadKilograms, let reps = set.reps else { continue }
                    let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
                    best[entry.exercise.name] = max(best[entry.exercise.name] ?? 0, e1rm)
                }
            }
        }
        return best
    }

    static let seedExercises: [Exercise] = [
        Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"]),
        Exercise(name: "Barbell Back Squat", aliases: ["squat", "squats", "back squat"]),
        Exercise(name: "Conventional Deadlift", aliases: ["deadlift", "deads"]),
        Exercise(name: "Overhead Press", aliases: ["ohp", "overhead press", "press"]),
        Exercise(name: "Barbell Row", aliases: ["row", "barbell row", "bent row"]),
        Exercise(name: "Pull-Up", aliases: ["pull up", "pull ups", "pullups"]),
    ]
}
