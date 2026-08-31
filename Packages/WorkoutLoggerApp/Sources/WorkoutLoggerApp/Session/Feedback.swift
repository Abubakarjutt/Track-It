import Foundation

/// What the app should say (or not say) back after an utterance.
public enum ReadbackPlan: Equatable, Sendable {
    case speak(String)
    case earcon
}

/// The distinct haptic patterns the session fires. `none` means "no haptic".
public enum HapticCue: Equatable, Sendable {
    case logged
    case notCaught
    case personalRecord
    case restReached
    case none
}

/// Push-to-talk speech capture. `beginUtterance` on press, `endUtterance` on
/// release yields the recogniser's final n-best hypotheses (best first).
public protocol TranscriptSource: AnyObject {
    func beginUtterance()
    func endUtterance() async throws -> [String]
}

/// Speaks a readback plan (or plays the earcon tone).
public protocol ReadbackVoice: AnyObject {
    func perform(_ plan: ReadbackPlan)
}

/// Plays one of the fixed haptic patterns.
public protocol Haptics: AnyObject {
    func play(_ cue: HapticCue)
}
