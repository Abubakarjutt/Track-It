import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("Set formatting")
struct SetFormattingTests {

    private func set(
        effort: EffortMeasure = .reps, role: SetRole = .working, grouping: Grouping = .straight,
        kg: Double? = nil, reps: Int? = nil, seconds: Int? = nil, metres: Double? = nil
    ) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: effort, role: role, grouping: grouping,
            loadKilograms: kg, reps: reps, durationSeconds: seconds, distanceMeters: metres,
            loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("numberString drops a trailing .0 but keeps real fractions")
    func numberStringRule() {
        #expect(numberString(100) == "100")
        #expect(numberString(2.5) == "2.5")
    }

    @Test("a rep set with load renders load, unit, and reps")
    func repsWithLoad() {
        #expect(formattedSetLine(set(kg: 100, reps: 5), unit: .kilograms) == "100 kg × 5")
    }

    @Test("pounds preference converts the stored kilograms back")
    func poundsConversion() {
        // 100 lb spoken -> engine stores 100 * 0.45359237 kg -> shown back as "100 lb"
        let stored = 100 * 0.45359237
        #expect(formattedSetLine(set(kg: stored, reps: 5), unit: .pounds) == "100 lb × 5")
    }

    @Test("a loadless rep set renders just the reps")
    func bodyweightReps() {
        #expect(formattedSetLine(set(kg: nil, reps: 12), unit: .kilograms) == "12 reps")
    }

    @Test("warmup and grouping markers are appended")
    func markers() {
        #expect(formattedSetLine(set(role: .warmup, kg: 60, reps: 10), unit: .kilograms) == "warm-up 60 kg × 10")
        #expect(formattedSetLine(set(grouping: .superset, kg: 100, reps: 5), unit: .kilograms) == "100 kg × 5 · superset")
        #expect(formattedSetLine(set(grouping: .dropset, kg: 80, reps: 8), unit: .kilograms) == "80 kg × 8 · dropset")
    }

    @Test("duration and distance efforts render their own units")
    func timedAndDistance() {
        #expect(formattedSetLine(set(effort: .duration, seconds: 45), unit: .kilograms) == "45s")
        #expect(formattedSetLine(set(effort: .distance, metres: 400), unit: .kilograms) == "400 m")
    }
}

@Suite("HUDProjection")
@MainActor
struct HUDProjectionTests {

    private static let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    private static let library = ExerciseLibrary([bench])

    private struct Rig { let model: WorkoutSessionModel; let source: ScriptedTranscriptSource }

    private func makeRig(
        script: [[String]], unit: MassUnit = .kilograms,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library, unit: unit, now: now)
        let source = ScriptedTranscriptSource(script)
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: SpyReadbackVoice(),
            haptics: SpyHaptics(), library: Self.library, unit: unit, now: now
        )
        return Rig(model: model, source: source)
    }

    private func say(_ rig: Rig) async { rig.model.pressed(); await rig.model.released() }

    @Test("a fresh model projects placeholders")
    func freshModel() throws {
        let p = HUDProjection(from: try makeRig(script: []).model)
        #expect(p.exerciseName == "No exercise yet")
        #expect(p.lastSetLine == nil)
        #expect(p.restLine == nil)
        #expect(p.currentEntrySetLines.isEmpty)
        #expect(p.tapSelectCandidates == nil)
    }

    @Test("after a set the projection shows the exercise and the formatted line")
    func afterASet() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
        await say(rig); await say(rig)
        let p = HUDProjection(from: rig.model)
        #expect(p.exerciseName == "Bench Press")
        #expect(p.lastSetLine == "100 kg × 5")
        #expect(p.currentEntrySetLines == ["100 kg × 5"])
    }

    @Test("a pounds model renders the last set in pounds")
    func poundsModel() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]], unit: .pounds)
        await say(rig); await say(rig)
        #expect(HUDProjection(from: rig.model).lastSetLine == "100 lb × 5")
    }

    @Test("restLine counts up mm:ss and restTargetReached flips past the target")
    func restLine() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]], now: { clock })
        await say(rig); await say(rig)

        clock = Date(timeIntervalSince1970: 1_065) // 1:05
        rig.model.tick()
        var p = HUDProjection(from: rig.model)
        #expect(p.restLine == "1:05")
        #expect(p.restTargetReached == false)

        clock = Date(timeIntervalSince1970: 1_130) // past the 120s default
        rig.model.tick()
        p = HUDProjection(from: rig.model)
        #expect(p.restTargetReached == true)
    }

    @Test("the swipe-up list carries warmup and superset markers")
    func setListMarkers() async throws {
        // The real parser's `warmup` form is `warmup <load> [unit] for <reps>` — it
        // takes no name, so the exercise must already be active. Likewise `superset`
        // is an exact command phrase. So the warmup set follows a bare `bench`
        // announcement, and the working set is spoken inside the superset run.
        let rig = try makeRig(script: [
            ["start workout"], ["bench"], ["warmup 60 for 10"],
            ["superset"], ["bench 100 for 5"], ["end superset"],
        ])
        for _ in 0..<6 { await say(rig) }
        let lines = HUDProjection(from: rig.model).currentEntrySetLines
        #expect(lines.count == 2)
        #expect(lines[0] == "warm-up 60 kg × 10")
        #expect(lines[1] == "100 kg × 5 · superset")
    }

    @Test("low-confidence input surfaces tap-select candidates on the projection")
    func tapSelectPassThrough() async throws {
        let rig = try makeRig(script: [["start workout"], ["flurbo"]])
        await say(rig); await say(rig)
        #expect(HUDProjection(from: rig.model).tapSelectCandidates != nil)
    }
}
