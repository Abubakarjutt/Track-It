import SwiftUI
import SwiftData
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Composition root. `@MainActor` (ruling from Task 7's fix round) so `init()`
/// may construct the `@MainActor` `System*` adapters and the `@MainActor`
/// `WorkoutSessionModel`.
@main
@MainActor
struct TrackitApp: App {
    @State private var model: WorkoutSessionModel

    init() {
        let container = try! ModelContainer(for: WorkoutRecord.self)
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let library = ExerciseLibrary(TrackitApp.seedExercises)
        let engine = WorkoutEngine(store: store, library: library)
        _model = State(initialValue: WorkoutSessionModel(
            engine: engine,
            transcriptSource: SystemSpeechRecognizer(),
            readbackVoice: SystemReadbackVoice(),
            haptics: SystemHaptics(),
            library: library
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
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
