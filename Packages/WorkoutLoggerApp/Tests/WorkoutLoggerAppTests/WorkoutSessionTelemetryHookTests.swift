import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutSessionModel telemetry + failed-utterance hooks")
@MainActor
struct WorkoutSessionTelemetryHookTests {

     private static let bench = Exercise(name: "Bench Press", aliases: ["bench"])
     private static let library = ExerciseLibrary([bench])

       /// Box so the session's escaping telemetry closure can record events
       /// without capturing a mutable local (Swift 6 concurrency).
     final class EventBox: @unchecked Sendable {
        var events: [TelemetryEvent] = []
        func add(_ e: TelemetryEvent) { events.append(e) }
       }

       /// Box so the session's escaping unresolved-utterance closure can capture
       /// transcripts without capturing a mutable local.
     final class TranscriptBox: @unchecked Sendable {
        var captured: [String] = []
        func add(_ t: String) { captured.append(t) }
       }

      private struct Rig {
        let model: WorkoutSessionModel
        let events: EventBox
        let unresolved: TranscriptBox
       }

    private func makeRig(
        script: [[String]],
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
      ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
          )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(
            store: store, library: Self.library, unit: .kilograms, now: now
          )
        let events = EventBox()
        let unresolved = TranscriptBox()
        let model = WorkoutSessionModel(
            engine: engine,
            transcriptSource: ScriptedTranscriptSource(script),
            readbackVoice: SpyReadbackVoice(),
            haptics: SpyHaptics(),
            library: Self.library,
            now: now,
            history: { store.history() },
            onTelemetry: { events.add($0) },
            onUnresolvedUtterance: { unresolved.add($0) }
          )
        return Rig(model: model, events: events, unresolved: unresolved)
       }

       private func say(_ rig: Rig) async {
        rig.model.pressed()
        await rig.model.released()
       }

       @Test("starting a workout emits workoutStarted")
    func startEmitsStarted() async throws {
        let rig = try makeRig(script: [["start workout"]])
        await say(rig)
        #expect(rig.events.events.contains(.workoutStarted))
       }

       @Test("each logged set emits a setLogged event")
    func eachSetEmitsSetLogged() async throws {
        let rig = try makeRig(script: [
            ["start workout"], ["bench 100 for 5"], ["bench 110 for 5"],
          ])
        for _ in 0..<3 { await say(rig) }
        #expect(rig.events.events.filter { $0 == .setLogged }.count == 2)
       }

       @Test("an unparseable utterance emits parseFailed and routes its transcript")
    func parseFailureEmitsAndRoutes() async throws {
        let rig = try makeRig(script: [["start workout"], ["flurbo"]])
        await say(rig) // start
        await say(rig) // flurbo — low confidence
        #expect(rig.events.events.contains(.parseFailed))
        #expect(rig.unresolved.captured.contains("flurbo"))
       }

       @Test("an undo emits a correctionMade event")
    func undoEmitsCorrection() async throws {
        let rig = try makeRig(script: [
            ["start workout"], ["bench 100 for 5"], ["undo"],
          ])
        for _ in 0..<3 { await say(rig) }
        #expect(rig.events.events.contains(.correctionMade))
       }

       @Test("ending a workout emits a content-free workoutCompleted event")
    func endEmitsCompleted() async throws {
        var clock = Date(timeIntervalSince1970: 0)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"], ["end workout"]],
            now: { clock }
          )
        await say(rig) // start (clock 0)
        await say(rig) // set
        clock = Date(timeIntervalSince1970: 40 * 60) // 40 min in
        await say(rig) // end

        guard case .workoutCompleted(let total, let working, let bucket)? = rig.events.events.last else {
            Issue.record("expected a workoutCompleted event, got \(rig.events.events)")
            return
        }
        #expect(total == 1)
        #expect(working == 1)
        #expect(bucket == .thirtyToFiftyMinutes)
       }

       @Test("a mid-workout set does not emit a workoutCompleted event")
    func midWorkoutSetDoesNotComplete() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
        await say(rig) // start
        await say(rig) // set, no end
        #expect(rig.events.events.contains {
            if case .workoutCompleted = $0 { return true }; return false
          } == false)
       }
}
