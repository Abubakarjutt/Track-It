import SwiftUI
import SwiftData
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Composition root. `@MainActor` so `init()` may build the `@MainActor`
/// `System*` adapters and the `@MainActor` models.
@main
@MainActor
struct TrackitApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model: WorkoutSessionModel
    private let historyModel: WorkoutHistoryModel
    private let settingsModel: SettingsModel
    private let onboardingModel: OnboardingModel
    private let store: SwiftDataWorkoutStore
    private let telemetryUploader: TelemetryUploader
    private let historyUnavailable: Bool
    // Retained only so its MPRemoteCommandCenter registration and
    // withObservationTracking loop stay alive for the app's lifetime
    // (cluster 7b) — never read after init.
    private let remotePushToTalk: RemoteCommandPushToTalk

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

        let degraded = availability.isDegraded
        let history = degraded ? [] : store.history()
        let knownBests = TrackitApp.knownBests(from: history)
        let engine = WorkoutEngine(
            store: store, library: library,
            unit: settingsStore.defaultUnit, knownBests: knownBests,
            knownBestsProvider: {
                TrackitApp.knownBests(from: degraded ? [] : store.history())
            }
        )

         let openWorkout = degraded ? nil : store.openWorkout()
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

        let healthSync = HealthKitSyncModel(
            store: SystemHealthKitWorkoutStore(),
            settings: settingsStore,
            syncedStore: SwiftDataSyncedWorkoutStore(context: context)
          )
        // A post-hoc edit to a workout that is already in Health re-syncs it.
        historyModel.onWorkoutEdited = { workout in
            Task { @MainActor in await healthSync.workoutEdited(workout) }
        }

        let telemetryUploader = TelemetryUploader(
            transport: TelemetryHTTPTransport(),
            queueStore: FileTelemetryQueueStore()
        )
        self.telemetryUploader = telemetryUploader
        let telemetry = TelemetryRecorder(sink: telemetryUploader, settings: settingsStore)
        let failedUtterances = FailedUtteranceModel(
            store: SystemFailedUtteranceStore(), settings: settingsStore
          )

        let session = WorkoutSessionModel(
            engine: engine,
            transcriptSource: SystemSpeechRecognizer(),
            readbackVoice: SystemReadbackVoice(),
            haptics: SystemHaptics(),
            library: library,
            unit: settingsStore.defaultUnit,
            knownBestExercises: Set(knownBests.keys.map(\.name)),
            staleRecovery: staleRecovery,
            history: { store.history() },
            onWorkoutEnded: { workout in
                Task { @MainActor in await healthSync.workoutEnded(workout) }
               },
            onTelemetry: { telemetry.record($0) },
            onUnresolvedUtterance: { failedUtterances.capture($0) }
           )
      _model = State(initialValue: session)
        self.remotePushToTalk = RemoteCommandPushToTalk(session: session)

        self.settingsModel = SettingsModel(
            settingsStore: settingsStore,
            libraryStore: libraryStore,
            speechAuthorization: speechAuth,
            session: session,
            historyModel: historyModel,
            seed: defaultExerciseSeed,
            telemetry: telemetry,
            failedUtterances: failedUtterances,
            healthSync: healthSync
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let uploader = telemetryUploader
                Task { await uploader.flush() }
            }
        }
    }

    /// Best estimated 1RM per exercise across completed history — the PR bar each
    /// exercise must clear this app run. Keyed on the whole `Exercise` value (1d),
    /// matching `WorkoutEngine`'s per-exercise maps.
    ///
    /// Keys come from persisted `Workout` entries; the engine looks them up with
    /// library-resolved values. If a curated exercise's alias list changes between
    /// releases the two stop comparing equal, so that exercise's bar seeds from 0
    /// until the lifter sets a fresh PR — an accepted, self-healing discontinuity.
    /// A stable `Exercise` identity field would remove it (deferred, cluster 2).
    static func knownBests(from history: [Workout]) -> [Exercise: Double] {
        var best: [Exercise: Double] = [:]
        for workout in history {
            for entry in workout.entries {
                for set in entry.sets where set.role == .working {
                    guard let load = set.loadKilograms, let reps = set.reps else { continue }
                    let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
                    best[entry.exercise] = max(best[entry.exercise] ?? 0, e1rm)
                }
            }
        }
        return best
    }
}
