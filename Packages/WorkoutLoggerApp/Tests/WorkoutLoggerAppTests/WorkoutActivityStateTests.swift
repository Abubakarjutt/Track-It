import Testing
import SwiftData
import Foundation
@testable import WorkoutLoggerApp
import WorkoutLoggerCore

@Suite("WorkoutActivityState")
@MainActor
struct WorkoutActivityStateTests {
    private static let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    private static let library = ExerciseLibrary([bench])

    private func makeModel(script: [[String]]) throws -> WorkoutSessionModel {
        let container = try ModelContainer(
            for: WorkoutRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library)
        let source = ScriptedTranscriptSource(script)
        return WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: SpyReadbackVoice(),
            haptics: SpyHaptics(), library: Self.library
        )
    }

    private func say(_ model: WorkoutSessionModel) async {
        model.pressed()
        await model.released()
    }

    @Test("reflects current exercise, working-set count, and rest deadline")
    func reflectsCurrentState() async throws {
        let model = try makeModel(script: [["start workout"], ["bench 100 for 5"]])
        await say(model)
        await say(model)
        let state = WorkoutActivityState(from: model)
        #expect(state?.exerciseName == "Bench Press")
        #expect(state?.workingSetCount == 1)
        #expect(state?.isResting == true)
        #expect(state?.restDeadline == model.restDeadline)
    }

    @Test("is nil with no active workout")
    func nilWithNoWorkout() throws {
        let model = try makeModel(script: [])
        #expect(WorkoutActivityState(from: model) == nil)
    }

    @Test("goes nil when the workout ends")
    func nilAfterWorkoutEnds() async throws {
        let model = try makeModel(script: [["start workout"], ["end workout"]])
        await say(model)
        await say(model)
        #expect(WorkoutActivityState(from: model) == nil)
    }
}
