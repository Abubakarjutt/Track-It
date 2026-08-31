import Testing
import Foundation
import WorkoutLoggerCore

@Suite("Workout Codable round-trip")
struct WorkoutCodableTests {

    @Test("a workout exercising every axis survives JSON encode/decode")
    func roundTrip() throws {
        let set = LoggedSet(
            loadType: .added, effort: .reps, role: .working, grouping: .superset,
            loadKilograms: 42.5, reps: 8, durationSeconds: nil, distanceMeters: nil,
            supersetRunID: 2, loggedAt: Date(timeIntervalSince1970: 1_234),
            note: "felt heavy"
        )
        let timed = LoggedSet(
            loadType: .bodyweight, effort: .duration, role: .warmup, grouping: .straight,
            loadKilograms: nil, reps: nil, durationSeconds: 60, distanceMeters: nil,
            supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: 1_300), note: nil
        )
        let workout = Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press", aliases: ["bench"]), sets: [set, timed])],
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 5_000),
            note: "morning session"
        )

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(Workout.self, from: data)

        #expect(decoded == workout)
    }

    @Test("a personal record round-trips")
    func personalRecordRoundTrip() throws {
        let pr = PersonalRecord(exercise: Exercise(name: "Squat"), estimatedOneRepMaxKilograms: 180.25)
        let data = try JSONEncoder().encode(pr)
        #expect(try JSONDecoder().decode(PersonalRecord.self, from: data) == pr)
    }
}
