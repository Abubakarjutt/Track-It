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

    /// The one rig builder: an in-memory SwiftData stack, an engine, and a
    /// session wired to event/transcript boxes. Callers vary only the
    /// `TranscriptSource` and the clock — everything else is fixed here so the
    /// scripted and clock-advancing rigs can't drift apart.
    private func makeRig(
        transcriptSource: TranscriptSource,
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
            transcriptSource: transcriptSource,
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

       /// A rig driven by a fixed script through `ScriptedTranscriptSource`.
    private func makeRig(
        script: [[String]],
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
      ) throws -> Rig {
        try makeRig(transcriptSource: ScriptedTranscriptSource(script), now: now)
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

    /// A mutable clock the fake transcript source advances mid-utterance, so a
    /// test can put real elapsed time between press-release and set-logged.
    final class ClockBox: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    /// Advances `clock` by `step` seconds inside `endUtterance()` — modelling
    /// the recogniser + parse time the latency span is meant to capture.
    final class DelayingTranscriptSource: TranscriptSource {
        private var scripts: [[String]]
        private let clock: ClockBox
        private let step: TimeInterval
        init(_ scripts: [[String]], clock: ClockBox, step: TimeInterval) {
            self.scripts = scripts; self.clock = clock; self.step = step
        }
        func beginUtterance() {}
        func endUtterance() async throws -> [String] {
            clock.date = clock.date.addingTimeInterval(step)
            return scripts.isEmpty ? [] : scripts.removeFirst()
        }
    }

    /// A rig whose `endUtterance()` advances `clock` by `step` seconds, so a
    /// test can put real elapsed time into the press→logged latency span.
    private func makeDelayingRig(
        script: [[String]], clock: ClockBox, step: TimeInterval
    ) throws -> Rig {
        try makeRig(
            transcriptSource: DelayingTranscriptSource(script, clock: clock, step: step),
            now: { clock.date }
        )
    }

    /// `endUtterance()` always throws — the recogniser failing after the press.
    /// No transcript reaches the parser, so `released()` bails before `apply`.
    final class FailingTranscriptSource: TranscriptSource {
        struct Failure: Error {}
        func beginUtterance() {}
        func endUtterance() async throws -> [String] { throw Failure() }
    }

    @Test("a logged set emits one setLoggedLatency bucket for the press→logged span")
    func loggedSetEmitsLatency() async throws {
        let clock = ClockBox(Date(timeIntervalSince1970: 0))
        let rig = try makeDelayingRig(
            script: [["start workout"], ["bench 100 for 5"]], clock: clock, step: 0.4
        )
        await say(rig)  // start workout — logs no set
        await say(rig)  // bench 100 for 5 — logs a set, ~0.4 s elapsed

        let latencies = rig.events.events.compactMap { event -> Int? in
            if case let .setLoggedLatency(bucket) = event { return bucket }
            return nil
        }
        #expect(latencies == [400])
    }

    @Test("an utterance that logs nothing emits no latency event")
    func noSetNoLatency() async throws {
        let clock = ClockBox(Date(timeIntervalSince1970: 0))
        let rig = try makeDelayingRig(script: [["flurbo"]], clock: clock, step: 0.4)
        await say(rig)
        #expect(rig.events.events.contains {
            if case .setLoggedLatency = $0 { return true }; return false
        } == false)
    }

    @Test("a thrown endUtterance() logs nothing and emits no latency event")
    func endUtteranceThrowEmitsNoLatency() async throws {
        let rig = try makeRig(transcriptSource: FailingTranscriptSource())
        await say(rig)
        // released() bails in its catch before apply(), so not one event fires
        // and no transcript is routed for review — there was no transcript.
        #expect(rig.events.events.isEmpty)
        #expect(rig.unresolved.captured.isEmpty)
    }

    @Test("setLogged still fires exactly once per set alongside the latency event")
    func setLoggedUnaffected() async throws {
        let clock = ClockBox(Date(timeIntervalSince1970: 0))
        let rig = try makeDelayingRig(
            script: [["start workout"], ["bench 100 for 5"], ["bench 110 for 5"]],
            clock: clock, step: 0.2
        )
        for _ in 0..<3 { await say(rig) }
        #expect(rig.events.events.filter { $0 == .setLogged }.count == 2)
        #expect(rig.events.events.filter {
            if case .setLoggedLatency = $0 { return true }; return false
        }.count == 2)
    }
}
