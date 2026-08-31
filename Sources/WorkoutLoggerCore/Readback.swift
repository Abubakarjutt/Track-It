// Readback — how loudly to confirm a just-processed utterance. Pure and
// synchronous: a parser result and two flags in, a style out. No TTS, no audio.
// The app maps the style to terse speech, full speech, or an earcon.
// See specs/v1-voice-logging.md (Readback module, stories 19–22).

/// How the app should confirm an utterance back to the lifter.
public enum ReadbackStyle: Equatable, Sendable {
    /// Just the numbers, e.g. "225 for 5" — the confident common case.
    case terse
    /// The whole thing, e.g. "Logged. Bench press, 225 pounds for 5 reps." —
    /// used the first time an exercise comes up in the workout.
    case full
    /// A non-speech tone. The user has capped readback at earcon, or the result
    /// is a bare command that needs only an acknowledgement.
    case earcon
}

/// Chooses the readback style for `result`. `isNewExercise` is true the first
/// time an exercise is used in the current workout; `capAtEarcon` is the user's
/// "earcon only" setting and overrides everything.
///
/// Confidence gating (spec line 325 — a shaky parse gets a full readback) is not
/// wired here yet: the parser reports a confidence score only on `.lowConfidence`
/// results, so there is nothing to gate a `.set` or `.announcement` on. When the
/// parser starts reporting confidence on confident results, add the threshold
/// check back here.
public func readbackStyle(
    for result: ParseResult,
    isNewExercise: Bool,
    capAtEarcon: Bool
) -> ReadbackStyle {
    if capAtEarcon { return .earcon }

    switch result {
    case .lowConfidence:
        return .full
    case .set, .announcement:
        return isNewExercise ? .full : .terse
    case .command:
        return .earcon
    }
}
