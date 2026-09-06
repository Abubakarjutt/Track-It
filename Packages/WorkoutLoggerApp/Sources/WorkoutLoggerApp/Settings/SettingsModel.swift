import Foundation
import Observation
import WorkoutLoggerCore

/// Owns the live preference values and the derived exercise library, and
/// pushes unit / library changes one-directionally into the session (which
/// forwards to the engine). Persistence is split: unit + onboarding flag in
/// `SettingsStore` (UserDefaults); the library in `ExerciseLibraryStore`
/// (SwiftData). "Delete all workout data" is orchestrated here but touches
/// only the workout store.
@MainActor
@Observable
public final class SettingsModel {
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let libraryStore: ExerciseLibraryStore
    @ObservationIgnored private let speechAuthorization: SpeechAuthorization
    @ObservationIgnored private let session: WorkoutSessionModel
    @ObservationIgnored private let historyModel: WorkoutHistoryModel
    @ObservationIgnored private let telemetry: TelemetryRecorder
    @ObservationIgnored private let failedUtterances: FailedUtteranceModel
    @ObservationIgnored private let healthSync: HealthKitSyncModel

    private var _unit: MassUnit
    public private(set) var exercises: [Exercise]
    public private(set) var speechStatus: SpeechAuthorizationStatus
    /// The two privacy opt-ins — mirrored so the Privacy section re-renders on
    /// toggle without reading through the `@ObservationIgnored` store.
    public private(set) var analyticsEnabled: Bool
    public private(set) var recognitionReviewEnabled: Bool
    /// The Apple Health opt-in and its authorization state, mirrored so the
    /// section re-renders on toggle and permission change.
    public private(set) var healthSyncEnabled: Bool
    public private(set) var healthSyncStatus: HealthKitSyncStatus

    public init(
        settingsStore: SettingsStore,
        libraryStore: ExerciseLibraryStore,
        speechAuthorization: SpeechAuthorization,
        session: WorkoutSessionModel,
        historyModel: WorkoutHistoryModel,
        seed: [Exercise] = defaultExerciseSeed,
        telemetry: TelemetryRecorder? = nil,
        failedUtterances: FailedUtteranceModel? = nil,
        healthSync: HealthKitSyncModel? = nil
      ) {
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.speechAuthorization = speechAuthorization
        self.session = session
        self.historyModel = historyModel
        self.telemetry = telemetry
            ?? TelemetryRecorder(sink: NoopTelemetrySink(), settings: settingsStore)
        self.failedUtterances = failedUtterances
            ?? FailedUtteranceModel(store: NoopFailedUtteranceStore(), settings: settingsStore)
        self.healthSync = healthSync
            ?? HealthKitSyncModel(store: NoopHealthKitWorkoutStore(), settings: settingsStore)

        libraryStore.seedIfEmpty(seed)
        self._unit = settingsStore.defaultUnit
        self.exercises = libraryStore.all()
        self.speechStatus = speechAuthorization.status
        self.analyticsEnabled = settingsStore.analyticsEnabled
        self.recognitionReviewEnabled = settingsStore.recognitionReviewEnabled
        self.healthSyncEnabled = self.healthSync.isEnabled
        self.healthSyncStatus = self.healthSync.status

        session.updateDefaultUnit(_unit)
        session.updateLibrary(ExerciseLibrary(exercises))
      }

    /// The kg/lb default. Setting it (to a new value) persists and pushes
    /// live to the session and engine. `_unit` is a plain stored property so
    /// `@Observable` tracks reads of `unit` through it.
    public var unit: MassUnit {
        get { _unit }
        set {
            guard newValue != _unit else { return }
            _unit = newValue
            settingsStore.defaultUnit = newValue
            session.updateDefaultUnit(newValue)
        }
    }

    /// The library as it currently stands — what gets pushed on any edit.
    public var currentLibrary: ExerciseLibrary { ExerciseLibrary(exercises) }

    // MARK: - Exercise library

    /// Add a Custom exercise. Throws `ExerciseLibraryError` on an empty or
    /// duplicate (case-insensitive) name, mutating nothing in that case.
    public func addExercise(name: String, aliases: [String]) throws {
        let exercise = try ExerciseLibraryValidation.validated(
            name: name, aliases: aliases, against: exercises
        )
        libraryStore.add(exercise)
        refreshLibrary()
    }

    /// Rename and/or re-alias an existing Exercise. Same naming rule as
    /// `addExercise`, except the record being edited is not its own
    /// collision — a case-only rename or an alias-only edit is allowed.
    public func updateExercise(named originalName: String, toName newName: String, aliases: [String]) throws {
        let exercise = try ExerciseLibraryValidation.validated(
            name: newName, aliases: aliases, against: exercises, renaming: originalName
        )
        libraryStore.update(named: originalName, to: exercise)
        refreshLibrary()
    }

    /// Remove an Exercise. Past Workouts that reference it are unaffected —
    /// they embed `Exercise` by value.
    public func deleteExercise(named name: String) {
        libraryStore.delete(named: name)
        refreshLibrary()
    }

    private func refreshLibrary() {
        exercises = libraryStore.all()
        session.updateLibrary(currentLibrary)
    }

    // MARK: - Speech

    /// Re-read speech authorization — call on Settings `.onAppear` and when
    /// the app returns to the foreground, since the user can change it in
    /// iOS Settings and come back.
    public func refreshSpeechStatus() {
        speechStatus = speechAuthorization.status
    }

    /// Whether to show the "Open iOS Settings" recovery row. Only `denied`
    /// is recoverable there; `unavailable` is a device/locale limitation.
    public var showsSpeechRecoveryRow: Bool { speechStatus == .denied }

    // MARK: - Delete all workout data

    /// False while a Workout is open — the destructive action is disabled
    /// with an explanatory footer in that state.
    public var canDeleteAllWorkoutData: Bool { !session.hasActiveWorkout }

    /// Erase every stored Workout. The Exercise library and preferences are
    /// separate stores and survive. No-op while a Workout is open. After the
    /// wipe the session's personal-record celebration gate is re-derived from
    /// the now-empty history.
    public func deleteAllWorkoutData() {
        guard canDeleteAllWorkoutData else { return }
        historyModel.deleteAllWorkoutData()
        session.refreshKnownBests()
    }

     // MARK: - Apple Health

     /// Re-read HealthKit authorization — call on Settings `.onAppear` and when
     /// the app returns to the foreground, since the user can change it in the
     /// Health app or iOS Settings and come back.
     public func refreshHealthStatus() {
        healthSync.refreshStatus()
        healthSyncEnabled = healthSync.isEnabled
        healthSyncStatus = healthSync.status
       }

      /// Flip the Apple Health opt-in. Enabling requests authorization and emits
      /// the `healthSyncToggle` feature event; disabling stops all future writes
      /// without touching what is already in Health.
     public func setHealthSyncEnabled(_ enabled: Bool) async {
        await healthSync.setEnabled(enabled)
        healthSyncEnabled = healthSync.isEnabled
        healthSyncStatus = healthSync.status
        telemetry.record(.featureUsed(.healthSyncToggle))
        }

      /// Whether to show the "Open iOS Settings" recovery row. Only `denied` is
      /// recoverable there; `unavailable` is a device limitation and `notDetermined`
      /// is resolved by the toggle itself.
     public var showsHealthRecoveryRow: Bool { healthSyncStatus == .denied }

     // MARK: - Export

     /// Re-read the completed-workout list — call on Settings `.onAppear` so the
     /// Export row reflects a workout finished since this model was built.
     public func refreshHistory() {
        historyModel.reload()
       }

    /// False when there is nothing completed to back up — the Export row is
    /// disabled with an explanatory footer in that state (spec story 23).
    public var canExportHistory: Bool { !historyModel.rows.isEmpty }

     /// Serialise the completed training history for the share sheet. The pure
     /// builder does the work; the view writes the bytes out and presents them.
     /// `now` stamps the archive and the file name (injected for tests).
    public func exportDocument(format: ExportFormat, now: Date = Date()) -> ExportDocument {
        telemetry.record(.featureUsed(.export))
        return WorkoutHistoryExport.document(for: historyModel.rows, format: format, generatedAt: now)
      }

      // MARK: - Privacy

       /// Re-read the recognition-review queue — call on Settings `.onAppear` so
        /// the "Review N phrases" row reflects phrases captured since this model
        /// was built.
    public func refreshRecognitionReview() {
        failedUtterances.refreshPending()
       }

       /// Whether the "Review N phrases" row shows.
    public var hasQueuedPhrases: Bool { failedUtterances.pendingCount > 0 }
    public var queuedPhraseCount: Int { failedUtterances.pendingCount }

       /// The phrases a lifter can review, submit, or discard.
    public var pendingUtterances: [PendingUtterance] { failedUtterances.pending }

        /// Flip the analytics opt-in. Disabling stops delivery immediately.
    public func setAnalyticsEnabled(_ enabled: Bool) {
        telemetry.setEnabled(enabled)
        analyticsEnabled = telemetry.isEnabled
        telemetry.record(.featureUsed(.analyticsToggle))
        }

        /// Flip the failed-utterance opt-in. Disabling stops capture; the queue
         /// can still be worked through or cleared.
    public func setRecognitionReviewEnabled(_ enabled: Bool) {
        failedUtterances.setEnabled(enabled)
        recognitionReviewEnabled = failedUtterances.isEnabled
        telemetry.record(.featureUsed(.recognitionReviewToggle))
        }

       /// Submit chosen phrases for upload; they leave the queue.
    public func submitPhrases(_ utterances: [PendingUtterance]) {
        failedUtterances.submit(utterances)
       }

       /// Discard chosen phrases without uploading; they leave the queue.
    public func discardPhrases(_ utterances: [PendingUtterance]) {
        failedUtterances.discard(utterances)
       }

       /// Clear the whole queue when the lifter opts out.
    public func clearQueuedPhrases() {
        failedUtterances.clearAll()
       }

       /// Note that the lifter opened Settings — a `.featureUsed` event.
    public func recordSettingsOpened() {
        telemetry.record(.featureUsed(.settingsOpened))
       }
}
