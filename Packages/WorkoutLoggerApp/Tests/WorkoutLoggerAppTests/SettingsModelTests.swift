import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {

    struct Rig {
        let settings: SettingsModel
        let settingsStore: InMemorySettingsStore
        let libraryStore: InMemoryExerciseLibraryStore
        let speech: FakeSpeechAuthorization
        let session: WorkoutSessionModel
        let history: WorkoutHistoryModel
    }

    func makeRig(
        settingsStore: InMemorySettingsStore = InMemorySettingsStore(),
        libraryStore: InMemoryExerciseLibraryStore = InMemoryExerciseLibraryStore(),
        speech: FakeSpeechAuthorization = FakeSpeechAuthorization(status: .granted),
        seed: [Exercise] = [Exercise(name: "Bench Press", aliases: ["bench"])]
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self, ExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: .empty)
        let session = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource([]),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: .empty,
            history: { store.history() }
        )
        let history = WorkoutHistoryModel(store: store)
        let settings = SettingsModel(
            settingsStore: settingsStore, libraryStore: libraryStore,
            speechAuthorization: speech, session: session, historyModel: history, seed: seed
        )
        return Rig(settings: settings, settingsStore: settingsStore, libraryStore: libraryStore,
                   speech: speech, session: session, history: history)
    }

    @Test("init seeds an empty library and exposes it alphabetically")
    func initSeeds() throws {
        let rig = try makeRig(seed: [
            Exercise(name: "Squat"), Exercise(name: "Bench Press"),
        ])
        #expect(rig.settings.exercises.map(\.name) == ["Bench Press", "Squat"])
        #expect(rig.libraryStore.all().count == 2)
    }

    @Test("init does not reseed a populated library")
    func initNoReseed() throws {
        let libraryStore = InMemoryExerciseLibraryStore()
        libraryStore.add(Exercise(name: "Deadlift"))
        let rig = try makeRig(libraryStore: libraryStore, seed: [Exercise(name: "Bench Press")])
        #expect(rig.settings.exercises.map(\.name) == ["Deadlift"])
    }

    @Test("init pushes the loaded library into the session")
    func initPushesLibrary() throws {
        let libraryStore = InMemoryExerciseLibraryStore()
        libraryStore.add(Exercise(name: "Overhead Press", aliases: ["ohp"]))
        let rig = try makeRig(libraryStore: libraryStore)

        #expect(rig.settings.currentLibrary.exercises.map(\.name) == ["Overhead Press"])
    }

    @Test("unit is read from the store and, when changed, persisted and pushed to the session")
    func unitGetSet() throws {
        let rig = try makeRig(settingsStore: InMemorySettingsStore(defaultUnit: .pounds))
        #expect(rig.settings.unit == .pounds)
        #expect(rig.session.displayUnit == .pounds)

        rig.settings.unit = .kilograms

        #expect(rig.settingsStore.defaultUnit == .kilograms)
        #expect(rig.session.displayUnit == .kilograms)
    }

    @Test("addExercise persists, refreshes the list, and pushes the library live")
    func addExercisePushes() throws {
        let rig = try makeRig(seed: [Exercise(name: "Bench Press")])

        try rig.settings.addExercise(name: "Romanian Deadlift", aliases: ["rdl", "romanians"])

        #expect(rig.settings.exercises.map(\.name) == ["Bench Press", "Romanian Deadlift"])
        #expect(rig.libraryStore.all().map(\.name).contains("Romanian Deadlift"))
        #expect(rig.settings.currentLibrary.exercises.contains { $0.aliases.contains("rdl") })
    }

    @Test("updateExercise renames, re-aliases, and re-sorts")
    func updateExercise() throws {
        let rig = try makeRig(seed: [Exercise(name: "Row"), Exercise(name: "Curl")])

        try rig.settings.updateExercise(named: "Row", toName: "Zzz Row", aliases: ["pendlay"])

        #expect(rig.settings.exercises.map(\.name) == ["Curl", "Zzz Row"])
        #expect(rig.settings.exercises.last?.aliases == ["pendlay"])
    }

    @Test("deleteExercise removes it and pushes the smaller library")
    func deleteExercise() throws {
        let rig = try makeRig(seed: [Exercise(name: "Bench Press"), Exercise(name: "Squat")])

        rig.settings.deleteExercise(named: "Squat")

        #expect(rig.settings.exercises.map(\.name) == ["Bench Press"])
        #expect(rig.settings.currentLibrary.exercises.map(\.name) == ["Bench Press"])
    }

    @Test("a rejected add changes nothing")
    func rejectedAddIsInert() throws {
        let rig = try makeRig(seed: [Exercise(name: "Bench Press")])

        #expect(throws: ExerciseLibraryError.duplicateName) {
            try rig.settings.addExercise(name: "bench press", aliases: [])
        }
        #expect(rig.settings.exercises.map(\.name) == ["Bench Press"])
    }

    @Test("addExercise rejects an empty name and changes nothing")
    func addRejectsEmptyName() throws {
        let rig = try makeRig(seed: [Exercise(name: "Bench Press")])

        #expect(throws: ExerciseLibraryError.emptyName) {
            try rig.settings.addExercise(name: "   ", aliases: [])
        }
        #expect(rig.settings.exercises.map(\.name) == ["Bench Press"])
        #expect(rig.libraryStore.all().map(\.name) == ["Bench Press"])
    }

    @Test("updateExercise rejects renaming onto another exercise's name and changes nothing")
    func updateRejectsCollision() throws {
        let rig = try makeRig(seed: [Exercise(name: "Bench Press"), Exercise(name: "Squat")])

        #expect(throws: ExerciseLibraryError.duplicateName) {
            try rig.settings.updateExercise(named: "Squat", toName: "bench press", aliases: [])
        }
        #expect(rig.settings.exercises.map(\.name) == ["Bench Press", "Squat"])
    }

    @Test("updateExercise allows a case-only rename plus alias edit of the same record")
    func updateAllowsCaseOnlyRename() throws {
        let rig = try makeRig(seed: [Exercise(name: "Squat")])

        try rig.settings.updateExercise(named: "Squat", toName: "SQUAT", aliases: ["back squat"])

        #expect(rig.settings.exercises.map(\.name) == ["SQUAT"])
        #expect(rig.settings.exercises.first?.aliases == ["back squat"])
    }

    @Test("speech status is read on init and re-read on refresh")
    func speechStatusRefresh() throws {
        let speech = FakeSpeechAuthorization(status: .notDetermined)
        let rig = try makeRig(speech: speech)
        #expect(rig.settings.speechStatus == .notDetermined)

        speech.set(.denied)
        rig.settings.refreshSpeechStatus()

        #expect(rig.settings.speechStatus == .denied)
    }

    @Test("the recovery row shows for denied only")
    func recoveryRowVisibility() throws {
        let cases: [(SpeechAuthorizationStatus, Bool)] = [
            (.granted, false), (.notDetermined, false), (.denied, true), (.unavailable, false),
        ]
        for (status, shows) in cases {
            let rig = try makeRig(speech: FakeSpeechAuthorization(status: status))
            #expect(rig.settings.showsSpeechRecoveryRow == shows)
        }
    }

    // A session wired to a real in-memory store, plus a SettingsModel over it.
    private func makeDeleteRig(
        script: [[String]], seededHistory: [Workout] = [], knownBestExercises: Set<String> = []
    ) throws -> (SettingsModel, WorkoutSessionModel, SwiftDataWorkoutStore, WorkoutHistoryModel) {
        let container = try ModelContainer(
            for: WorkoutRecord.self, ExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        for workout in seededHistory { store.save(workout) }
        let bench = Exercise(name: "Bench Press", aliases: ["bench"])
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        let session = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource(script),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(),
            library: ExerciseLibrary([bench]), knownBestExercises: knownBestExercises,
            history: { store.history() }
        )
        let history = WorkoutHistoryModel(store: store)
        let settings = SettingsModel(
            settingsStore: InMemorySettingsStore(), libraryStore: InMemoryExerciseLibraryStore(),
            speechAuthorization: FakeSpeechAuthorization(), session: session,
            historyModel: history, seed: [bench]
        )
        return (settings, session, store, history)
    }

    @Test("delete-all is blocked while a workout is open")
    func deleteBlockedMidWorkout() async throws {
        let (settings, session, store, _) = try makeDeleteRig(
            script: [["start workout"], ["bench"], ["100 for 5"]]
        )
        session.pressed(); await session.released() // start
        session.pressed(); await session.released() // bench
        session.pressed(); await session.released() // 100 for 5
        #expect(settings.canDeleteAllWorkoutData == false)

        settings.deleteAllWorkoutData() // no-op

        #expect(store.history().isEmpty == false)
    }

    @Test("export builds a document from the completed history; disabled when empty")
    func exportHistory() throws {
        let done = Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [LoggedSet(
                loadType: .external, effort: .reps, role: .working, grouping: .straight,
                loadKilograms: 100, reps: 5, durationSeconds: nil, distanceMeters: nil,
                supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: 10), note: nil)])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 3_600)
        )
        let (withHistory, _, _, _) = try makeDeleteRig(script: [], seededHistory: [done])
        #expect(withHistory.canExportHistory)

        let document = withHistory.exportDocument(
            format: .json, now: Date(timeIntervalSince1970: 86_400)
        )
        let archive = try JSONDecoder().decode(WorkoutArchive.self, from: document.data)
        #expect(archive.workouts == [done])
        #expect(document.suggestedFilename == "trackit-1970-01-02.json")

        let (empty, _, _, _) = try makeDeleteRig(script: [])
        #expect(empty.canExportHistory == false)
    }

    @Test("delete-all clears rows and the PR gate when no workout is open")
    func deleteClearsWhenIdle() async throws {
        let done = Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [LoggedSet(
                loadType: .external, effort: .reps, role: .working, grouping: .straight,
                loadKilograms: 140, reps: 3, durationSeconds: nil, distanceMeters: nil,
                supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: 10), note: nil)])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 100)
        )
        let (settings, _, store, history) = try makeDeleteRig(
            script: [], seededHistory: [done], knownBestExercises: ["Bench Press"]
        )
        #expect(history.rows.count == 1)
        #expect(settings.canDeleteAllWorkoutData == true)

        settings.deleteAllWorkoutData()

        #expect(history.rows.isEmpty)
        #expect(store.history().isEmpty)
    }
}
