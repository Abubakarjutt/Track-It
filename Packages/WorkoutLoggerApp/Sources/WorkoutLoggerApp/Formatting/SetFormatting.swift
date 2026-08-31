import Foundation
import WorkoutLoggerCore

/// Whole numbers without a trailing `.0` (`100`), real fractions kept (`2.5`).
/// The single rule for every prominent number the app shows or speaks.
func numberString(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
}

private let kilogramsPerPound = 0.45359237

/// Rounds to one decimal place, absorbing the float slop a kg↔lb conversion
/// leaves behind before `numberString` decides whole-vs-fraction.
private func gymRound(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

/// One display line for a logged set: load + unit + reps (or reps alone, or a
/// timed / distance value), a `warm-up ` prefix for warmups, and a
/// ` · superset` / ` · dropset` suffix for grouped sets.
func formattedSetLine(_ set: LoggedSet, unit: MassUnit) -> String {
    var line: String
    switch set.effort {
    case .reps:
        let reps = set.reps ?? 0
        if let kg = set.loadKilograms, kg > 0 {
            let shown = gymRound(unit == .pounds ? kg / kilogramsPerPound : kg)
            let word = unit == .pounds ? "lb" : "kg"
            line = "\(numberString(shown)) \(word) × \(reps)"
        } else {
            line = "\(reps) reps"
        }
    case .duration:
        line = "\(set.durationSeconds ?? 0)s"
    case .distance:
        line = "\(numberString(gymRound(set.distanceMeters ?? 0))) m"
    }
    if set.role == .warmup { line = "warm-up " + line }
    switch set.grouping {
    case .superset: line += " · superset"
    case .dropset:  line += " · dropset"
    case .straight: break
    }
    return line
}
