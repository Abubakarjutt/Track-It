import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SettingsModel Apple Health")
@MainActor
struct SettingsModelHealthTests {

     private struct Rig {
        let settings: SettingsModel
        let settingsStore: InMemorySettingsStore
        let health: FakeHealthKitWorkoutStore
        let telemetry: CaptureTelemetrySink
      }

     private func makeRig(
        settingsStore: InMemorySettingsStore,
        health: FakeHealthKitWorkoutStore,
        telemetry: CaptureTelemetrySink = CaptureTelemetrySink()
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
        let sync = HealthKitSyncModel(store: health, settings: settingsStore)
        let settings = SettingsModel(
            settingsStore: settingsStore,
            libraryStore: InMemoryExerciseLibraryStore(),
            speechAuthorization: FakeSpeechAuthorization(status: .granted),
            session: session, historyModel: history,
            telemetry: recorder, healthSync: sync
            )
         return Rig(settings: settings, settingsStore: settingsStore, health: health, telemetry: telemetry)
      }

      @Test("the health-sync flag and status are read from the store and model on init")
     func readsFlagAndStatus() throws {
        let store = InMemorySettingsStore(syncsToAppleHealth: true)
        let health = FakeHealthKitWorkoutStore(status: .authorized)
        let rig = try makeRig(settingsStore: store, health: health)

         #expect(rig.settings.healthSyncEnabled)
         #expect(rig.settings.healthSyncStatus == .authorized)
      }

      @Test("toggling health sync on flips the flag, requests authorization, and emits the telemetry event")
     func enablingAuthorizesAndEmits() async throws {
        // Analytics must already be on for the recorder to forward the event
        // (story 31: off stops delivery), so this test opts analytics in first.
        let store = InMemorySettingsStore(analyticsEnabled: true)
        let health = FakeHealthKitWorkoutStore(status: .notDetermined, statusAfterRequest: .authorized)
        let rig = try makeRig(settingsStore: store, health: health)

         #expect(rig.settings.healthSyncEnabled == false)
         #expect(health.authorizationRequests == 0)

        await rig.settings.setHealthSyncEnabled(true)

         #expect(rig.settingsStore.syncsToAppleHealth)
         #expect(rig.settings.healthSyncEnabled)
         #expect(health.authorizationRequests == 1)
         #expect(health.status == .authorized)
         #expect(rig.telemetry.events.contains(.featureUsed(.healthSyncToggle)))
      }

      @Test("refreshing health status re-reads the store after an external permission change")
     func refreshStatusRereads() throws {
        let store = InMemorySettingsStore(syncsToAppleHealth: true)
        let health = FakeHealthKitWorkoutStore(status: .authorized)
        let rig = try makeRig(settingsStore: store, health: health)
         #expect(rig.settings.healthSyncStatus == .authorized)

        health.set(.denied)
        rig.settings.refreshHealthStatus()

         #expect(rig.settings.healthSyncStatus == .denied)
      }

      @Test("toggling health sync off stops it without touching authorization")
     func disablingStopsSync() async throws {
        let store = InMemorySettingsStore(syncsToAppleHealth: true)
        let health = FakeHealthKitWorkoutStore(status: .authorized)
        let rig = try makeRig(settingsStore: store, health: health)

         await rig.settings.setHealthSyncEnabled(false)

         #expect(rig.settingsStore.syncsToAppleHealth == false)
         #expect(rig.settings.healthSyncEnabled == false)
         #expect(health.authorizationRequests == 0)
      }
}
