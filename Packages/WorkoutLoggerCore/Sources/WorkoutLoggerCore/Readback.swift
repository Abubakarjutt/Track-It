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

/// A parse whose confidence is below this reads back in full even for a familiar
/// exercise — story 20's "fuller when unsure". Shares the resolver's
/// confident-match bar; split it out if the two ever need to diverge.
let readbackConfidenceFloor = confidentMatchThreshold

/// Chooses the readback style for `result`. `isNewExercise` is true the first
/// time an exercise is used in the current workout; `capAtEarcon` is the user's
/// "earcon only" setting and overrides everything. A `.set` or `.announcement`
/// whose confidence is below `readbackConfidenceFloor` reads back in full
/// regardless of familiarity (story 20 — a shaky parse gets the full readback).
public func readbackStyle(
    for result: ParseResult,
    isNewExercise: Bool,
    capAtEarcon: Bool
) -> ReadbackStyle {
    if capAtEarcon { return .earcon }

    switch result {
    case .lowConfidence:
        return .full
    case let .set(_, confidence), let .announcement(_, confidence):
        if confidence < readbackConfidenceFloor { return .full }
        return isNewExercise ? .full : .terse
    case .command:
        return .earcon
    }
}
