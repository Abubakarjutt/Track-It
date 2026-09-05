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
        try libraryStore.add(Exercise(name: "Deadlift"))
        let rig = try makeRig(libraryStore: libraryStore, seed: [Exercise(name: "Bench Press")])
        #expect(rig.settings.exercises.map(\.name) == ["Deadlift"])
    }

    @Test("init pushes the loaded library into the session")
    func initPushesLibrary() throws {
        let libraryStore = InMemoryExerciseLibraryStore()
        try libraryStore.add(Exercise(name: "Overhead Press", aliases: ["ohp"]))
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
}
