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

    @Test("CSV export is one row per set beneath a header, with loads in kilograms")
    func csvRowPerSet() {
        let workout = Workout(
            entries: [
                Entry(exercise: Exercise(name: "Bench Press"), sets: [
                    LoggedSet(loadType: .external, effort: .reps, role: .warmup, grouping: .straight,
                              loadKilograms: 60, reps: 10,
                              loggedAt: Date(timeIntervalSince1970: 10)),
                    LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                              loadKilograms: 100, reps: 5,
                              loggedAt: Date(timeIntervalSince1970: 90)),
                ]),
                Entry(exercise: Exercise(name: "Plank"), sets: [
                    LoggedSet(loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
                              durationSeconds: 60,
                              loggedAt: Date(timeIntervalSince1970: 200)),
                ]),
            ],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 3_600)
        )

        let document = WorkoutHistoryExport.document(
            for: [workout], format: .csv, generatedAt: Date(timeIntervalSince1970: 86_400)
        )
        let lines = String(decoding: document.data, as: UTF8.self).split(
            separator: "\n", omittingEmptySubsequences: false
        )

        #expect(lines.first == "workout_started_at,workout_ended_at,exercise,load_type,effort,role,grouping,load_kilograms,load_unit,reps,duration_seconds,distance_meters,superset_run_id,note")
        #expect(lines.count == 4)
        #expect(lines[1] == "1970-01-01T00:00:00Z,1970-01-01T01:00:00Z,Bench Press,external,reps,warmup,straight,60,kg,10,,,,")
        #expect(lines[2] == "1970-01-01T00:00:00Z,1970-01-01T01:00:00Z,Bench Press,external,reps,working,straight,100,kg,5,,,,")
        #expect(lines[3] == "1970-01-01T00:00:00Z,1970-01-01T01:00:00Z,Plank,bodyweight,duration,working,straight,,kg,,60,,,")
    }

    @Test("CSV fields carrying a comma, quote, or newline are RFC 4180 quoted")
    func csvQuotesAwkwardFields() {
        let workout = Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5,
                          loggedAt: Date(timeIntervalSince1970: 10),
                          note: "felt strong, \"easy\"\nnext: +5kg"),
            ])],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 3_600)
        )

        let document = WorkoutHistoryExport.document(
            for: [workout], format: .csv, generatedAt: Date(timeIntervalSince1970: 86_400)
        )
        let text = String(decoding: document.data, as: UTF8.self)

        #expect(text.hasSuffix(",\"felt strong, \"\"easy\"\"\nnext: +5kg\""))
        // The embedded newline stays inside the quoted field, so the payload is
        // still exactly two physical lines: header + the one set row.
        #expect(text.split(separator: "\n", omittingEmptySubsequences: false).count == 3)
    }

    @Test("empty history still produces a well-formed document in each format")
    func emptyHistoryIsWellFormed() throws {
        let when = Date(timeIntervalSince1970: 86_400)

        let json = WorkoutHistoryExport.document(for: [], format: .json, generatedAt: when)
        let archive = try JSONDecoder().decode(WorkoutArchive.self, from: json.data)
        #expect(archive.workouts.isEmpty)
        #expect(archive.schemaVersion == WorkoutArchive.currentSchemaVersion)

        let csv = WorkoutHistoryExport.document(for: [], format: .csv, generatedAt: when)
        let text = String(decoding: csv.data, as: UTF8.self)
        #expect(text == "workout_started_at,workout_ended_at,exercise,load_type,effort,role,grouping,load_kilograms,load_unit,reps,duration_seconds,distance_meters,superset_run_id,note")
    }

    @Test("workouts are emitted oldest-first whatever order they arrive in")
    func ordersChronologically() throws {
        let older = completed("Squat", [set(140, 3, at: 100)], from: 0, to: 3_600)
        let newer = completed("Bench Press", [set(100, 5, at: 10_100)], from: 10_000, to: 12_000)

        // History screens hand these over newest-first.
        let document = WorkoutHistoryExport.document(
            for: [newer, older], format: .json, generatedAt: Date(timeIntervalSince1970: 86_400)
        )

        let archive = try JSONDecoder().decode(WorkoutArchive.self, from: document.data)
        #expect(archive.workouts == [older, newer])
    }
}
