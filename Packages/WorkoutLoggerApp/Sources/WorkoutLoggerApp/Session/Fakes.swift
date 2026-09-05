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

/// A `TranscriptSource` whose `endUtterance()` suspends until the test
/// explicitly `resume(with:)`s it — for asserting on state that only holds
/// during the real async gap between releasing the talk button and the
/// transcript resolving, which `ScriptedTranscriptSource` resolves through
/// too fast to observe.
public final class GatedTranscriptSource: TranscriptSource {
    // A queue, not a single slot: a quick press-release-press-release starts
    // a second endUtterance() before the first has resolved, and both ports
    // are `@MainActor` today so nothing here guarantees only one is ever in
    // flight. FIFO on both sides — install order matches resume order — so
    // resume(with:) always answers the call that's been waiting longest.
    private var continuations: [CheckedContinuation<[String], Error>] = []
    // Buffers a resume(with:) that arrives before its matching endUtterance()
    // has installed a continuation, so it's honored instead of silently
    // discarded — which would otherwise hang that caller forever rather than
    // failing the test.
    private var pendingHypotheses: [[String]] = []
    public private(set) var beganCount = 0
    /// Continuations installed and not yet resumed — lets a test wait for N
    /// overlapping `endUtterance()` calls to actually suspend before it
    /// starts resuming them, so a multi-release test's ordering is
    /// deterministic rather than racing the awaits.
    public var waitingCount: Int { continuations.count }
    public init() {}

    public func beginUtterance() {
        beganCount += 1
    }

    public func endUtterance() async throws -> [String] {
        if !pendingHypotheses.isEmpty {
            return pendingHypotheses.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    public func resume(with hypotheses: [String]) {
        if !continuations.isEmpty {
            continuations.removeFirst().resume(returning: hypotheses)
        } else {
            pendingHypotheses.append(hypotheses)
        }
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
