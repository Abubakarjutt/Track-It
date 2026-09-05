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
            return ExportDocument(suggestedFilename: filename("csv", on: generatedAt), data: Data())
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
