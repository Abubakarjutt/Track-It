import Foundation
import WorkoutLoggerCore

/// Turns a parser result + a chosen `ReadbackStyle` into the concrete thing the
/// app says. Pure. Speaks the set's values *as spoken* (the parser's `load` /
/// `loadUnit`), so "225 pounds" is read back in pounds. Unit-preference
/// conversion is a later polish, not needed to confirm an utterance.
public func readbackPlan(
    for result: ParseResult,
    style: ReadbackStyle,
    exerciseName: String?
) -> ReadbackPlan {
    if style == .earcon { return .earcon }

    switch result {
    case .command:
        return .earcon
    case .lowConfidence:
        return .speak("Didn't catch that.")
    case .announcement(let exercise):
        return .speak("\(exercise.name).")
    case .set(let set):
        switch style {
        case .earcon:
            return .earcon
        case .terse:
            return .speak(terseBody(set))
        case .full:
            let lead = exerciseName.map { "\($0), " } ?? ""
            return .speak("Logged. \(lead)\(fullBody(set)).")
        }
    }
}

private func terseBody(_ set: ParsedSet) -> String {
    switch set.effort {
    case .reps:
        if let load = set.load, let reps = set.reps {
            return "\(number(load)) for \(reps)"
        }
        return "\(set.reps ?? 0) reps"
    case .duration:
        return "\(set.durationSeconds ?? 0) seconds"
    case .distance:
        return "\(number(set.distanceMeters ?? 0)) meters"
    }
}

private func fullBody(_ set: ParsedSet) -> String {
    switch set.effort {
    case .reps:
        if let load = set.load, let reps = set.reps {
            return "\(number(load)) \(unitWord(set.loadUnit)) for \(reps) reps"
        }
        return "\(set.reps ?? 0) reps"
    case .duration:
        return "\(set.durationSeconds ?? 0) seconds"
    case .distance:
        return "\(number(set.distanceMeters ?? 0)) meters"
    }
}

private func unitWord(_ unit: MassUnit?) -> String {
    switch unit {
    case .pounds: return "pounds"
    case .kilograms, .none: return "kilograms"
    }
}

private func number(_ value: Double) -> String {
    numberString(value)
}
