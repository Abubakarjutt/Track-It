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

    private var _unit: MassUnit
    public private(set) var exercises: [Exercise]
    public private(set) var speechStatus: SpeechAuthorizationStatus

    public init(
        settingsStore: SettingsStore,
        libraryStore: ExerciseLibraryStore,
        speechAuthorization: SpeechAuthorization,
        session: WorkoutSessionModel,
        historyModel: WorkoutHistoryModel,
        seed: [Exercise] = defaultExerciseSeed
    ) {
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.speechAuthorization = speechAuthorization
        self.session = session
        self.historyModel = historyModel

        libraryStore.seedIfEmpty(seed)
        self._unit = settingsStore.defaultUnit
        self.exercises = libraryStore.all()
        self.speechStatus = speechAuthorization.status

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
        try libraryStore.add(Exercise(name: name, aliases: aliases))
        refreshLibrary()
    }

    /// Rename and/or re-alias an existing Exercise.
    public func updateExercise(named originalName: String, toName newName: String, aliases: [String]) throws {
        try libraryStore.update(named: originalName, to: Exercise(name: newName, aliases: aliases))
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
}
