import Foundation
import WorkoutLoggerCore

/// The serialised form of a lifter's completed training history: a thin envelope
/// around the Core `Workout` values, which are already `Codable`. `schemaVersion`
/// lets a future importer tell archive formats apart; `exportedAt` records when
/// the file was produced. Dates use the encoder's default (numeric) strategy so
/// the archive is exactly lossless — a whole-`Double` `Date` survives the round
/// trip with no truncation.
public struct WorkoutArchive: Equatable, Sendable, Codable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var workouts: [Workout]

    public init(
        schemaVersion: Int = WorkoutArchive.currentSchemaVersion,
        exportedAt: Date,
        workouts: [Workout]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.workouts = workouts
    }

    public static let currentSchemaVersion = 1
}

/// The two file shapes an export can take. JSON is the lossless archive; CSV is
/// one row per Set for a spreadsheet.
public enum ExportFormat: Equatable, Sendable {
    case json
    case csv
}

/// A finished export ready to hand to the iOS share sheet: a suggested file name
/// and the bytes. Carries no I/O — the caller writes it out and presents it.
public struct ExportDocument: Equatable, Sendable {
    public var suggestedFilename: String
    public var data: Data

    public init(suggestedFilename: String, data: Data) {
        self.suggestedFilename = suggestedFilename
        self.data = data
    }
}

/// Pure builder: `[Workout]` in, `ExportDocument` out. `swift test`-covered so the
/// `App/` layer is only a file write plus a share sheet.
public enum WorkoutHistoryExport {

    public static func document(
        for workouts: [Workout], format: ExportFormat, generatedAt: Date
    ) -> ExportDocument {
        let completed = workouts.filter(\.isEnded)
        switch format {
        case .json:
            let archive = WorkoutArchive(exportedAt: generatedAt, workouts: completed)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(archive)) ?? Data()
            return ExportDocument(suggestedFilename: filename("json", on: generatedAt), data: data)
        case .csv:
            let text = csv(for: completed)
            return ExportDocument(
                suggestedFilename: filename("csv", on: generatedAt),
                data: Data(text.utf8)
            )
        }
    }

    // MARK: - CSV

    private static let csvHeader = [
        "workout_started_at", "workout_ended_at", "exercise",
        "load_type", "effort", "role", "grouping",
        "load_kilograms", "load_unit", "reps", "duration_seconds",
        "distance_meters", "superset_run_id", "note",
    ]

    /// One row per Set, flattening its owning workout and entry onto it. Loads
    /// are the stored kilograms (ADR-0002) — `load_unit` is always `kg`, never a
    /// conversion to the lifter's display unit, so a number in the file is never
    /// ambiguous.
    private static func csv(for workouts: [Workout]) -> String {
        var rows = [csvHeader.joined(separator: ",")]
        for workout in workouts {
            let started = workout.startedAt.ISO8601Format()
            let ended = workout.endedAt?.ISO8601Format() ?? ""
            for entry in workout.entries {
                for set in entry.sets {
                    rows.append(csvRow(started: started, ended: ended, entry: entry, set: set))
                }
            }
        }
        return rows.joined(separator: "\n")
    }

    private static func csvRow(started: String, ended: String, entry: Entry, set: LoggedSet) -> String {
        [
            started,
            ended,
            field(entry.exercise.name),
            loadTypeText(set.loadType),
            effortText(set.effort),
            roleText(set.role),
            groupingText(set.grouping),
            number(set.loadKilograms),
            "kg",
            set.reps.map(String.init) ?? "",
            set.durationSeconds.map(String.init) ?? "",
            number(set.distanceMeters),
            set.supersetRunID.map(String.init) ?? "",
            field(set.note ?? ""),
        ].joined(separator: ",")
    }

    /// A whole number prints without a trailing `.0`; anything else keeps its
    /// natural decimal form. `nil` is an empty cell.
    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }

    /// RFC 4180 quoting: wrap in double quotes and double any embedded quote when
    /// the value carries a comma, quote, or newline.
    private static func field(_ raw: String) -> String {
        guard raw.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return raw
        }
        return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func loadTypeText(_ t: LoadType) -> String {
        switch t {
        case .external: "external"
        case .bodyweight: "bodyweight"
        case .added: "added"
        case .assisted: "assisted"
        }
    }
    private static func effortText(_ e: EffortMeasure) -> String {
        switch e {
        case .reps: "reps"
        case .duration: "duration"
        case .distance: "distance"
        }
    }
    private static func roleText(_ r: SetRole) -> String {
        switch r {
        case .working: "working"
        case .warmup: "warmup"
        }
    }
    private static func groupingText(_ g: Grouping) -> String {
        switch g {
        case .straight: "straight"
        case .superset: "superset"
        case .dropset: "dropset"
        }
    }

    private static func filename(_ ext: String, on date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "trackit-\(stamp).\(ext)"
    }
}
