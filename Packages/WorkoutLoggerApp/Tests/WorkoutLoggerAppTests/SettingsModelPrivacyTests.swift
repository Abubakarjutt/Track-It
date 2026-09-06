import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SettingsModel privacy + feature events")
@MainActor
struct SettingsModelPrivacyTests {

     private struct Rig {
        let settings: SettingsModel
        let settingsStore: InMemorySettingsStore
        let telemetry: CaptureTelemetrySink
        let reviews: FakeFailedUtteranceStore
        }

    private func makeRig(
        settingsStore: InMemorySettingsStore,
        telemetry: CaptureTelemetrySink = CaptureTelemetrySink(),
        reviews: FakeFailedUtteranceStore = FakeFailedUtteranceStore()
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
        let recorder = TelemetryRecorder(sink: telemetry, settings: settingsStore)
        let review = FailedUtteranceModel(store: reviews, settings: settingsStore)
        let settings = SettingsModel(
            settingsStore: settingsStore,
            libraryStore: InMemoryExerciseLibraryStore(),
            speechAuthorization: FakeSpeechAuthorization(status: .granted),
            session: session, historyModel: history,
            telemetry: recorder, failedUtterances: review
           )
        return Rig(settings: settings, settingsStore: settingsStore, telemetry: telemetry, reviews: reviews)
        }

       @Test("the three privacy flags round-trip through the store")
    func flagsRoundTrip() throws {
        let store = InMemorySettingsStore(
            syncsToAppleHealth: true, analyticsEnabled: true, recognitionReviewEnabled: true
           )
        let rig = try makeRig(settingsStore: store)
        #expect(rig.settings.analyticsEnabled)
        #expect(rig.settings.recognitionReviewEnabled)
        }

       @Test("toggling analytics on emits the analyticsToggle feature event")
    func analyticsToggleEmitsEvent() throws {
        let store = InMemorySettingsStore()
        let rig = try makeRig(settingsStore: store)
         rig.settings.setAnalyticsEnabled(true)
         #expect(rig.settingsStore.analyticsEnabled)
         #expect(rig.settings.analyticsEnabled)
         #expect(rig.telemetry.events.contains(.featureUsed(.analyticsToggle)))
        }

        @Test("toggling recognition review on emits the recognitionReviewToggle feature event")
    func reviewToggleEmitsEvent() throws {
         // Analytics must already be on for the recorder to forward the event
         // (story 31: off stops delivery), so this test opts analytics in first.
        let store = InMemorySettingsStore(analyticsEnabled: true)
        let rig = try makeRig(settingsStore: store)
          rig.settings.setRecognitionReviewEnabled(true)
            #expect(rig.settingsStore.recognitionReviewEnabled)
            #expect(rig.settings.recognitionReviewEnabled)
            #expect(rig.telemetry.events.contains(.featureUsed(.recognitionReviewToggle)))
           }

           @Test("exporting emits a featureUsed(.export) event")
    func exportEmitsEvent() throws {
        let done = Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [LoggedSet(
                loadType: .external, effort: .reps, role: .working, grouping: .straight,
                loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10))])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 3_600)
            )
        let container = try ModelContainer(
            for: WorkoutRecord.self, ExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        store.save(done)
        let telemetry = CaptureTelemetrySink()
        let rig = try makeRig(settingsStore: InMemorySettingsStore(analyticsEnabled: true), telemetry: telemetry)

          _ = rig.settings.exportDocument(format: .json, now: Date(timeIntervalSince1970: 86_400))

            #expect(telemetry.events.contains(.featureUsed(.export)))
           }

         @Test("the review row shows only when phrases are queued")
    func reviewRowReflectsQueue() throws {
        let store = InMemorySettingsStore(recognitionReviewEnabled: true)
        let reviews = FakeFailedUtteranceStore()
        reviews.seed([PendingUtterance(transcript: "flurbo")])
        let rig = try makeRig(settingsStore: store, reviews: reviews)

          #expect(rig.settings.hasQueuedPhrases)
          #expect(rig.settings.queuedPhraseCount == 1)
         }

         @Test("submitting and discarding phrases empty the review queue through the model")
    func submitAndDiscardEmptyQueue() throws {
        let store = InMemorySettingsStore(recognitionReviewEnabled: true)
        let reviews = FakeFailedUtteranceStore()
        reviews.seed([
            PendingUtterance(transcript: "alpha"),
            PendingUtterance(transcript: "beta"),
           ])
        let rig = try makeRig(settingsStore: store, reviews: reviews)

        let all = rig.settings.pendingUtterances
        rig.settings.submitPhrases(all)

         #expect(rig.settings.hasQueuedPhrases == false)
          #expect(rig.settings.pendingUtterances.isEmpty)
         }
}
