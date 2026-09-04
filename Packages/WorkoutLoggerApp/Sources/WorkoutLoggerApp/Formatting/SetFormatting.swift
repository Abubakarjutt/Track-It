import Foundation
import WorkoutLoggerCore

/// Whole numbers without a trailing `.0` (`100`), real fractions kept (`2.5`).
/// The single rule for every prominent number the app shows or speaks.
func numberString(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
}

let kilogramsPerPound = 0.45359237

/// Rounds to one decimal place, absorbing the float slop a kg↔lb conversion
/// leaves behind before `numberString` decides whole-vs-fraction.
func gymRound(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

/// A load converted to the display unit and rounded, without a unit word — the
/// value a chart axis plots.
func displayLoad(_ kilograms: Double, unit: MassUnit) -> Double {
    gymRound(unit == .pounds ? kilograms / kilogramsPerPound : kilograms)
}

/// A load in the display unit, rounded and unit-labelled: "100 kg" / "137.5 lb".
func loadString(_ kilograms: Double, unit: MassUnit) -> String {
    "\(numberString(displayLoad(kilograms, unit: unit))) \(unit == .pounds ? "lb" : "kg")"
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
            line = "\(loadString(kg, unit: unit)) × \(reps)"
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
