import SwiftUI
import SwiftData
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Composition root. `@MainActor` so `init()` may build the `@MainActor`
/// `System*` adapters and the `@MainActor` models.
@main
@MainActor
struct TrackitApp: App {
    @State private var model: WorkoutSessionModel
    private let historyModel: WorkoutHistoryModel
    private let settingsModel: SettingsModel
    private let onboardingModel: OnboardingModel
    private let store: SwiftDataWorkoutStore
    private let historyUnavailable: Bool

    init() {
        let storeURL = URL.applicationSupportDirectory.appending(path: "Trackit.store")
        let availability = provisionStore(onDiskURL: storeURL)
        historyUnavailable = availability.isDegraded

        let context = ModelContext(availability.container)
        let store = SwiftDataWorkoutStore(context: context)
        self.store = store
        self.historyModel = WorkoutHistoryModel(
            store: store, historyUnavailable: availability.isDegraded
        )

        // Exercise library: seed on first launch, then read the user-owned set.
        // A degraded (in-memory) container isn't a trustworthy library, so fall
        // back to the seed there so common lifts still resolve.
        let libraryStore = SwiftDataExerciseLibraryStore(context: context)
        libraryStore.seedIfEmpty(defaultExerciseSeed)
        let library = ExerciseLibrary(
            availability.isDegraded ? defaultExerciseSeed : libraryStore.all()
        )

        let settingsStore = UserDefaultsSettingsStore()
        let speechAuth = SystemSpeechAuthorization()

        let history = availability.isDegraded ? [] : store.history()
        let knownBests = TrackitApp.knownBests(from: history)
        let engine = WorkoutEngine(
            store: store, library: library,
            unit: settingsStore.defaultUnit, knownBests: knownBests
        )

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

        let session = WorkoutSessionModel(
            engine: engine,
            transcriptSource: SystemSpeechRecognizer(),
            readbackVoice: SystemReadbackVoice(),
            haptics: SystemHaptics(),
            library: library,
            unit: settingsStore.defaultUnit,
            knownBestExercises: Set(knownBests.keys),
            staleRecovery: staleRecovery,
            history: { store.history() }
        )
        _model = State(initialValue: session)

        self.settingsModel = SettingsModel(
            settingsStore: settingsStore,
            libraryStore: libraryStore,
            speechAuthorization: speechAuth,
            session: session,
            historyModel: historyModel,
            seed: defaultExerciseSeed
        )
        self.onboardingModel = OnboardingModel(
            settingsStore: settingsStore, speechAuthorization: speechAuth
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                model: model, historyModel: historyModel, store: store,
                historyUnavailable: historyUnavailable,
                settingsModel: settingsModel, onboardingModel: onboardingModel
            )
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
}
