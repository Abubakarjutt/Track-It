// Seam A — the parser. Pure and synchronous: a transcript, the current workout
// context, and the exercise library in; an ordered list of results out.
// No I/O, no Speech framework. See specs/v1-voice-logging.md.
//
// `parse` tries a fixed, priority-ordered list of utterance forms and returns on
// the first whole-string match. The order is load-bearing:
//
//   1. commands              exact phrases — a command word is never a name
//   2. keyword load sets     "warmup / dropset / plus / assisted …" — the prefix
//                            disambiguates, so these precede the generic forms
//   3. straight set          "<load> [unit] for <reps>" — begins with a digit
//   4. inline set            "<name> <load> [unit] for <reps>"
//   5. duration / distance   "<name> for <n> seconds" / "<name> <n> metres"
//   6. bodyweight set        "<name> <n>" — the loosest pattern; must stay last
//   7. bare name             switch the active exercise
//
// If the generic "<name> …" forms ran before the keyword forms their greedy
// leading group would swallow "warmup", "plus", etc.; likewise the bodyweight
// form would swallow every "<name> <number>" utterance if it ran earlier.

import Foundation

// `confidentMatchThreshold` (defined in Resolver.swift) is the floor for
// auto-logging a set against a fuzzily-matched exercise name. Below it the
// utterance is reported low-confidence and nothing is logged — readback then goes
// full and the tap-select fallback can step in.

// Largest rep count the bare "<name> <n>" form accepts. Above this a lone number
// is almost always a dropped "for" ("bench 225" = 225 for N), so the parser
// flags it rather than logging a set nobody performed.
private let maxPlausibleReps = 100

// Largest spoken load any set form accepts, in whichever unit was spoken. 1000 kg
// is absurd and 1000 lb (454 kg) is past elite raw records, so a bigger number is
// a magnitude mis-hear ("five hundred" → "five thousand"), not a real lift.
private let maxPlausibleLoad = 1000.0

/// Whether a parsed set's numeric slots are within the range a real set occupies.
/// A `nil` slot (bodyweight load, a timed effort's reps) is not a value to doubt.
private func isPlausible(_ set: ParsedSet) -> Bool {
    if let reps = set.reps, reps > maxPlausibleReps { return false }
    if let load = set.load, load > maxPlausibleLoad { return false }
    return true
}

// MARK: - Patterns
//
// Built from shared fragments so the unit vocabulary is written once. Every
// pattern exposes named captures; `unit` is optional.

private let loadFragment = #"(?<load>\d+(?:\.\d+)?)"#
private let repsFragment = #"(?<reps>\d+)"#
private let unitFragment =
    #"(?:\s+(?<unit>kg|kgs|kilo|kilos|kilogram|kilograms|lb|lbs|pound|pounds))?"#

private func rx(_ pattern: String) -> Regex<AnyRegexOutput> {
    // Patterns are file-local literals; a build failure here is a programming bug.
    try! Regex(pattern).ignoresCase()
}

/// A form that produces a single `.set` with a load, a unit and a rep count.
/// Forms differ only by their regex and the axis constants they imply; each
/// exposes `load`, `reps` and an optional `unit` capture.
private struct LoadSetForm {
    let pattern: Regex<AnyRegexOutput>
    let loadType: LoadType
    let role: SetRole
    let grouping: Grouping
}

// The patterns are rebuilt per call rather than held in globals: `Regex` is not
// `Sendable`, and `parse` runs once per spoken set — not in a hot loop.
private func loadSetForms() -> [LoadSetForm] {
    [
        LoadSetForm(
            pattern: rx(#"warmup\s+\#(loadFragment)\#(unitFragment)\s+for\s+\#(repsFragment)"#),
            loadType: .external, role: .warmup, grouping: .straight
        ),
        LoadSetForm(
            pattern: rx(#"drop\s?set\s+\#(loadFragment)\#(unitFragment)\s+for\s+\#(repsFragment)"#),
            loadType: .external, role: .working, grouping: .dropset
        ),
        LoadSetForm(
            pattern: rx(#"plus\s+\#(loadFragment)\#(unitFragment)\s+for\s+\#(repsFragment)"#),
            loadType: .added, role: .working, grouping: .straight
        ),
        LoadSetForm(
            pattern: rx(#"assisted\s+\#(repsFragment)\s+minus\s+\#(loadFragment)\#(unitFragment)"#),
            loadType: .assisted, role: .working, grouping: .straight
        ),
        LoadSetForm(
            pattern: rx(#"\#(loadFragment)\#(unitFragment)\s+for\s+\#(repsFragment)"#),
            loadType: .external, role: .working, grouping: .straight
        ),
    ]
}

// MARK: - Parsing

public func parse(
    _ transcript: String,
    context: WorkoutContext,
    library: ExerciseLibrary
) -> [ParseResult] {
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return [] }

    let inlineSetPattern =
        rx(#"(?<name>.+?)\s+\#(loadFragment)\#(unitFragment)\s+for\s+\#(repsFragment)"#)
    let durationSetPattern =
        rx(#"(?<name>.+?)\s+for\s+(?<seconds>\d+)\s+(?:seconds|secs|sec|s)"#)
    let distanceSetPattern =
        rx(#"(?<name>.+?)\s+(?<meters>\d+(?:\.\d+)?)\s+(?:meters|metres|m)"#)
    let bodyweightSetPattern =
        rx(#"(?<name>.+?)\s+(?<reps>\d+)"#)

    // 1. Commands — exact phrases.
    switch text.lowercased() {
    case "undo":          return [.command(.undo)]
    case "start rest":    return [.command(.startRest)]
    case "skip rest":     return [.command(.skipRest)]
    case "help":          return [.command(.help)]
    case "start workout": return [.command(.startWorkout)]
    case "end workout":   return [.command(.endWorkout)]
    case "superset":      return [.command(.startSuperset)]
    case "end superset":  return [.command(.endSuperset)]
    default:              break
    }

    // 2–3. Keyword load sets, then the straight set.
    for form in loadSetForms() {
        guard let match = try? form.pattern.wholeMatch(in: text),
              let load = doubleCapture(match, "load"),
              let reps = intCapture(match, "reps")
        else { continue }
        let set = ParsedSet(
            loadType: form.loadType, effort: .reps, role: form.role, grouping: form.grouping,
            load: load, loadUnit: spokenMassUnit(stringCapture(match, "unit")) ?? context.unit,
            reps: reps
        )
        guard isPlausible(set) else {
            return [.lowConfidence(reason: .implausibleValue, bestGuesses: [])]
        }
        return [.set(set)]
    }

    // 4. Inline set — "<name> <load> [unit] for <reps>".
    if let match = try? inlineSetPattern.wholeMatch(in: text),
       let load = doubleCapture(match, "load"),
       let reps = intCapture(match, "reps") {
        return announce(stringCapture(match, "name"), in: library) { _ in
            ParsedSet(
                loadType: .external, effort: .reps, role: .working, grouping: .straight,
                load: load, loadUnit: spokenMassUnit(stringCapture(match, "unit")) ?? context.unit,
                reps: reps
            )
        }
    }

    // 5. Duration effort — "<name> for <n> seconds".
    if let match = try? durationSetPattern.wholeMatch(in: text),
       let seconds = intCapture(match, "seconds") {
        return announce(stringCapture(match, "name"), in: library) { _ in
            ParsedSet(
                loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
                durationSeconds: seconds
            )
        }
    }

    // 5. Distance effort — "<name> <n> metres".
    if let match = try? distanceSetPattern.wholeMatch(in: text),
       let meters = doubleCapture(match, "meters") {
        return announce(stringCapture(match, "name"), in: library) { _ in
            ParsedSet(
                loadType: .bodyweight, effort: .distance, role: .working, grouping: .straight,
                distanceMeters: meters
            )
        }
    }

    // 6. Bodyweight set — "<name> <n>". A number above the plausible-reps ceiling
    //    is a dropped "for", not a real rep count.
    if let match = try? bodyweightSetPattern.wholeMatch(in: text),
       let reps = intCapture(match, "reps") {
        switch matchInlineExercise(String(stringCapture(match, "name") ?? ""), in: library) {
        case .tooUnsure(let bestGuesses):
            return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: bestGuesses)]
        case .announce(let exercise) where reps > maxPlausibleReps:
            return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: [exercise])]
        case .announce(let exercise):
            return [.announcement(exercise), .set(ParsedSet(
                loadType: .bodyweight, effort: .reps, role: .working, grouping: .straight,
                reps: reps
            ))]
        }
    }

    // 7. A bare exercise name or alias — switch the active exercise. A leading
    //    "now" / "next" filler ("now squats") is dropped first. Anything the
    //    resolver still can't place is reported low-confidence rather than dropped.
    switch resolve(withoutAnnouncementLead(text), in: library) {
    case .resolved(let exercise, _):
        return [.announcement(exercise)]
    case .unresolved(let guesses):
        return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: guesses)]
    }
}

// MARK: - Inline exercise resolution

/// The exercise half of an inline "<name> <numbers>" utterance, once the numeric
/// slots have matched. `.announce` carries the exercise to log against;
/// `.tooUnsure` means the match is too weak to auto-log.
private enum InlineExercise {
    case announce(Exercise)
    case tooUnsure(bestGuesses: [Exercise])
}

private func matchInlineExercise(_ spokenName: String, in library: ExerciseLibrary) -> InlineExercise {
    switch resolve(spokenName, in: library) {
    case .resolved(let exercise, let confidence) where confidence >= confidentMatchThreshold:
        return .announce(exercise)
    case .resolved(let exercise, _):
        return .tooUnsure(bestGuesses: [exercise])
    case .unresolved(let guesses):
        return .tooUnsure(bestGuesses: guesses)
    }
}

/// On a confident match returns `[.announcement, .set(build(exercise))]`; on a
/// weak match returns a single `.lowConfidence` and logs nothing.
private func announce(
    _ spokenName: Substring?,
    in library: ExerciseLibrary,
    logging build: (Exercise) -> ParsedSet
) -> [ParseResult] {
    switch matchInlineExercise(String(spokenName ?? ""), in: library) {
    case .tooUnsure(let bestGuesses):
        return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: bestGuesses)]
    case .announce(let exercise):
        let set = build(exercise)
        guard isPlausible(set) else {
            return [.lowConfidence(reason: .implausibleValue, bestGuesses: [exercise])]
        }
        return [.announcement(exercise), .set(set)]
    }
}

// MARK: - Capture helpers

private func stringCapture(_ match: Regex<AnyRegexOutput>.Match, _ name: String) -> Substring? {
    match[name]?.substring
}

private func doubleCapture(_ match: Regex<AnyRegexOutput>.Match, _ name: String) -> Double? {
    stringCapture(match, name).flatMap { Double($0) }
}

private func intCapture(_ match: Regex<AnyRegexOutput>.Match, _ name: String) -> Int? {
    stringCapture(match, name).flatMap { Int($0) }
}

/// Drops a leading "now" / "next" filler from a bare announcement
/// ("now squats" → "squats") so the resolver matches on the exercise name alone.
/// Only reached once every set form has failed, so it cannot shadow a real set.
private func withoutAnnouncementLead(_ text: String) -> String {
    for lead in ["now ", "next "] where text.lowercased().hasPrefix(lead) {
        return String(text.dropFirst(lead.count))
    }
    return text
}

/// Maps a spoken unit word to a `MassUnit`. `nil` for no word or an unknown one.
private func spokenMassUnit(_ word: Substring?) -> MassUnit? {
    switch word?.lowercased() {
    case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms":
        return .kilograms
    case "lb", "lbs", "pound", "pounds":
        return .pounds
    default:
        return nil
    }
}
