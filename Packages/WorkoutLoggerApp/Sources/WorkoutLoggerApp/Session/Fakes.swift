import Foundation

/// A `TranscriptSource` that replays a fixed script — one entry per
/// `endUtterance()`. Used by tests and SwiftUI previews.
public final class ScriptedTranscriptSource: TranscriptSource {
    public enum Failure: Error { case exhausted }

    private var queue: [[String]]
    public var throwWhenExhausted = false
    public private(set) var beganCount = 0

    public init(_ queue: [[String]]) {
        self.queue = queue
    }

    public func beginUtterance() {
        beganCount += 1
    }

    public func endUtterance() async throws -> [String] {
        guard !queue.isEmpty else {
            if throwWhenExhausted { throw Failure.exhausted }
            return []
        }
        return queue.removeFirst()
    }
}

/// Records every readback plan it is handed.
public final class SpyReadbackVoice: ReadbackVoice {
    public private(set) var performed: [ReadbackPlan] = []
    public init() {}
    public func perform(_ plan: ReadbackPlan) { performed.append(plan) }
}

/// Records every haptic cue it is handed.
public final class SpyHaptics: Haptics {
    public private(set) var played: [HapticCue] = []
    public init() {}
    public func play(_ cue: HapticCue) { played.append(cue) }
}
