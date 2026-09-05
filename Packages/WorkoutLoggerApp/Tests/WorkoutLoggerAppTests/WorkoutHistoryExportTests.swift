import Foundation
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutHistoryExport")
struct WorkoutHistoryExportTests {

    private func set(_ load: Double, _ reps: Int, at seconds: TimeInterval) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: seconds))
    }

    private func completed(
        _ exercise: String, _ sets: [LoggedSet], from start: TimeInterval, to end: TimeInterval
    ) -> Workout {
        Workout(
            entries: [Entry(exercise: Exercise(name: exercise), sets: sets)],
            startedAt: Date(timeIntervalSince1970: start),
            endedAt: Date(timeIntervalSince1970: end)
        )
    }

    @Test("JSON export round-trips completed workouts losslessly")
    func jsonRoundTrips() throws {
        let workouts = [
            completed("Bench Press", [set(100, 5, at: 10), set(100, 5, at: 90)], from: 0, to: 3_600),
            completed("Squat", [set(140, 3, at: 4_000)], from: 3_800, to: 7_000),
        ]

        let document = WorkoutHistoryExport.document(
            for: workouts, format: .json, generatedAt: Date(timeIntervalSince1970: 86_400)
        )

        let archive = try JSONDecoder().decode(WorkoutArchive.self, from: document.data)
        #expect(archive.workouts == workouts)
    }

    @Test("an in-progress workout is left out of the archive")
    func excludesOpenWorkouts() throws {
        let done = completed("Bench Press", [set(100, 5, at: 10)], from: 0, to: 3_600)
        let open = Workout(
            entries: [Entry(exercise: Exercise(name: "Squat"), sets: [set(140, 3, at: 5_000)])],
            startedAt: Date(timeIntervalSince1970: 4_800), endedAt: nil
        )

        let document = WorkoutHistoryExport.document(
            for: [done, open], format: .json, generatedAt: Date(timeIntervalSince1970: 86_400)
        )

        let archive = try JSONDecoder().decode(WorkoutArchive.self, from: document.data)
        #expect(archive.workouts == [done])
    }

    @Test("the file name carries the generation date and the format's extension")
    func filenameCarriesDateAndExtension() {
        // 2026-09-05T12:00:00Z
        let when = Date(timeIntervalSince1970: 1_788_609_600)

        let json = WorkoutHistoryExport.document(for: [], format: .json, generatedAt: when)
        let csv = WorkoutHistoryExport.document(for: [], format: .csv, generatedAt: when)

        #expect(json.suggestedFilename == "trackit-2026-09-05.json")
        #expect(csv.suggestedFilename == "trackit-2026-09-05.csv")
    }
}
