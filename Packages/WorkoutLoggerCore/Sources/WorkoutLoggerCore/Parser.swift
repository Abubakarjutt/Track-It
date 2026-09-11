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
//   6. relative forms          "again" / "up 10" / "add a plate" / "back-off" —
//                            lean on context.previousSet; before bodyweight so a
//                             "<word> <n>" delta isn't read as a name + reps
//   7. bodyweight set          "<name> <n>" — the loosest name+number pattern
//   8. bare name              switch the active exercise
//
// If the generic "<name> …" forms ran before the keyword forms their greedy
// leading group would swallow "warmup", "plus", etc.; likewise the bodyweight
// form would swallow every "<name> <number>" utterance if it ran earlier. And the
// relative forms (step 6) must precede that bodyweight form — "up 10" / "add 10"
// otherwise read as a bare name plus a rep count — while still running after every
// explicit name+load form, so a fully-specified set wins over a relative one.

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

// One standard plate per unit, the increment "add a plate" / "drop a plate" moves
// by — a 20 kg plate, a 45 lb (competition) plate. Back-off rounds to the smallest
// fractional plate each side owns, 2.5 kg / 2.5 lb. See ADR-0004.
private func plateSize(for unit: MassUnit) -> Double {
    switch unit {
    case .kilograms: return 20
    case .pounds: return 45
    }
}
private func backOffRoundIncrement(for unit: MassUnit) -> Double {
    switch unit {
    case .kilograms, .pounds: return 2.5
    }
}

// Back-off is the previous load at this fraction, rounded to the smallest plate.
private let backOffFraction = 0.9

// Verbatim-repeat phrasings, normalised to lowercase.
private let repeatPhrases: Set<String> = [
    "again", "repeat", "same", "same again", "same as last", "same as last time",
]

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
        return [.set(set, confidence: 1.0)]
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

     // 6. Relative / contextual forms — lean on the previous set (cluster 1b).
     //    They run after every explicit name+load form so a fully-specified set
     //    wins, but before the bodyweight form so "up 10" / "add 10" aren't read
     //    as a bare name plus a rep count.
    if let relative = relativeSet(text, context: context) {
        return relative
       }

       // 7. Bodyweight set — "<name> <n>". A number above the plausible-reps ceiling
       //    is a dropped "for", not a real rep count.
    if let match = try? bodyweightSetPattern.wholeMatch(in: text),
       let reps = intCapture(match, "reps") {
        switch matchInlineExercise(String(stringCapture(match, "name") ?? ""), in: library) {
        case .tooUnsure(let bestGuesses):
            return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: bestGuesses)]
        case .announce(let exercise, _) where reps > maxPlausibleReps:
            return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: [exercise])]
        case .announce(let exercise, let confidence):
            return [.announcement(exercise, confidence: confidence), .set(ParsedSet(
                loadType: .bodyweight, effort: .reps, role: .working, grouping: .straight,
                reps: reps
            ), confidence: confidence)]
        }
    }

     // 8. A bare exercise name or alias — switch the active exercise. A leading
    //    "now" / "next" filler ("now squats") is dropped first. Anything the
    //    resolver still can't place is reported low-confidence rather than dropped.
    switch resolve(withoutAnnouncementLead(text), in: library) {
    case .resolved(let exercise, let confidence):
        return [.announcement(exercise, confidence: confidence)]
    case .unresolved(let guesses):
        return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: guesses)]
    }
}

// MARK: - Inline exercise resolution

/// The exercise half of an inline "<name> <numbers>" utterance, once the numeric
/// slots have matched. `.announce` carries the exercise to log against;
/// `.tooUnsure` means the match is too weak to auto-log.
private enum InlineExercise {
    case announce(Exercise, confidence: Double)
    case tooUnsure(bestGuesses: [Exercise])
}

private func matchInlineExercise(_ spokenName: String, in library: ExerciseLibrary) -> InlineExercise {
    switch resolve(spokenName, in: library) {
    case .resolved(let exercise, let confidence) where confidence >= confidentMatchThreshold:
        return .announce(exercise, confidence: confidence)
    case .resolved(let exercise, _):
        return .tooUnsure(bestGuesses: [exercise])
    case .unresolved(let guesses):
        return .tooUnsure(bestGuesses: guesses)
    }
}

/// On a confident match returns `[.announcement, .set(build(exercise))]`, both
/// carrying the resolver's score; on a weak match returns a single
/// `.lowConfidence` and logs nothing.
private func announce(
    _ spokenName: Substring?,
    in library: ExerciseLibrary,
    logging build: (Exercise) -> ParsedSet
) -> [ParseResult] {
    switch matchInlineExercise(String(spokenName ?? ""), in: library) {
    case .tooUnsure(let bestGuesses):
        return [.lowConfidence(reason: .unrecognisedExercise, bestGuesses: bestGuesses)]
    case .announce(let exercise, let confidence):
        let set = build(exercise)
        guard isPlausible(set) else {
            return [.lowConfidence(reason: .implausibleValue, bestGuesses: [exercise])]
        }
        return [.announcement(exercise, confidence: confidence), .set(set, confidence: confidence)]
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

// MARK: - Relative / contextual forms

/// The half of the parser context cluster 1b wired but `parse` never consumed: a
/// grammar that leans on `context.previousSet`. Each form is deterministic given
/// the previous set, so a match reports full confidence; with no previous set (or
/// no load to adjust) it returns nil so `parse` falls through and the utterance is
/// not silently logged. See ADR-0004 for the plate sizes and the back-off rounding.
private func relativeSet(_ text: String, context: WorkoutContext) -> [ParseResult]? {
    guard let previous = context.previousSet else { return nil }
    let unit = previous.loadUnit ?? context.unit
    let lowered = text.lowercased()

       // Repeat the previous set verbatim — the whole set, even a loadless one.
    if repeatPhrases.contains(lowered) {
        return [.set(previous, confidence: 1.0)]
       }

      // Every remaining form adjusts a load, so a loadless previous set (a timed or
      // distance effort) fails closed and is not a load form.
    guard let base = previous.load else { return nil }

    let backOff = rx(#"back[ -]?off(?:\s+set)?"#)
    let addPlate = rx(#"add\s+(?:a\s+|an\s+)?plate"#)
    let dropPlate = rx(#"drop\s+(?:a\s+|an\s+)?plate"#)
    let raise = rx(#"(?:up|add|plus)\s+(?<delta>\d+(?:\.\d+)?)"#)
    let lowerLeading = rx(#"(?:down|drop|less)\s+(?<delta>\d+(?:\.\d+)?)"#)
    let lowerTrailing = rx(#"(?<delta>\d+(?:\.\d+)?)\s+less"#)

       // Back-off: the previous load at 90%, rounded to the smallest plate.
    if let _ = try? backOff.wholeMatch(in: text) {
        let target = round(base * backOffFraction, to: backOffRoundIncrement(for: unit))
        return adjusted(previous, load: target, unit: unit, context: context)
       }

       // Plate steps — one standard plate per unit (ADR-0004).
    if let _ = try? addPlate.wholeMatch(in: text) {
        return adjusted(previous, load: base + plateSize(for: unit), unit: unit, context: context)
       }
    if let _ = try? dropPlate.wholeMatch(in: text) {
        return adjusted(previous, load: max(0, base - plateSize(for: unit)), unit: unit, context: context)
       }

       // Numeric delta in the context unit; a negative result floors at zero.
    if let match = try? raise.wholeMatch(in: text), let delta = doubleCapture(match, "delta") {
        return adjusted(previous, load: base + delta, unit: unit, context: context)
       }
    if let match = try? lowerLeading.wholeMatch(in: text), let delta = doubleCapture(match, "delta") {
        return adjusted(previous, load: max(0, base - delta), unit: unit, context: context)
       }
    if let match = try? lowerTrailing.wholeMatch(in: text), let delta = doubleCapture(match, "delta") {
        return adjusted(previous, load: max(0, base - delta), unit: unit, context: context)
       }

    return nil
}

/// A previous set with its load replaced by `load` (in `unit`), axes preserved.
/// The result is re-checked for plausibility so an out-of-range delta is flagged,
/// not logged; on an implausible value the active exercise is the best guess.
private func adjusted(
      _ previous: ParsedSet,
    load: Double,
    unit: MassUnit,
    context: WorkoutContext
) -> [ParseResult] {
    var set = previous
    set.load = load
    set.loadUnit = unit
    guard isPlausible(set) else {
        return [.lowConfidence(reason: .implausibleValue, bestGuesses: context.activeExercise.map { [$0] } ?? [])]
       }
    return [.set(set, confidence: 1.0)]
}

/// The nearest multiple of `increment` (half-up), used to round a back-off load to
/// a plate.
private func round(_ value: Double, to increment: Double) -> Double {
      (value / increment).rounded() * increment
}
